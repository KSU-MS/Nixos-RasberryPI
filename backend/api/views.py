"""
API views for KSUMS Data Offload Backend.
Handles listing MCAP files and recovering them via mcap-cli.
"""

import os
import shutil
import subprocess
import tempfile
import zipfile
import uuid
import logging
from pathlib import Path
from datetime import datetime

from django.conf import settings
from django.http import HttpResponse
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

logger = logging.getLogger(__name__)


@api_view(['GET'])
def health_check(request):
    """Health check endpoint for monitoring."""
    return Response({
        "status": "healthy",
        "service": "ksums-data-offload",
        "timestamp": datetime.now().isoformat()
    })


@api_view(['GET'])
def list_files(request):
    """
    List all .mcap files in the configured RECORDINGS_BASE_DIR.
    """
    base_dir = Path(settings.RECORDINGS_BASE_DIR)
    
    if not base_dir.exists():
        logger.warning(f"Recordings directory does not exist: {base_dir}")
        return Response({
            "error": f"Directory {base_dir} does not exist"
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    files_data = []
    try:
        for entry in os.scandir(base_dir):
            if entry.is_file() and entry.name.endswith('.mcap'):
                stat = entry.stat()
                files_data.append({
                    "name": entry.name,
                    "size": stat.st_size,
                    "createdAt": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                    "modifiedAt": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                })
        
        # Sort by modified date, newest first
        files_data.sort(key=lambda x: x['modifiedAt'], reverse=True)
        
        logger.info(f"Listed {len(files_data)} MCAP files from {base_dir}")
        
    except Exception as e:
        logger.error(f"Error listing files: {e}")
        return Response({
            "error": str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    return Response({
        "dir": str(base_dir),
        "files": files_data,
        "count": len(files_data)
    })


def resolve_inside(base, rel):
    """
    Safely resolve a relative path inside a base directory.
    Prevents path traversal attacks.
    """
    base_abs = Path(base).resolve()
    target_abs = (base_abs / rel).resolve()
    if base_abs not in target_abs.parents and base_abs != target_abs:
        raise ValueError("Path traversal detected")
    return target_abs


@api_view(['POST'])
def recover_and_zip(request):
    """
    Take a list of filenames, run 'mcap recover' on each,
    zip the results, and return the zip file.
    """
    files = request.data.get('files', [])
    if not files or not isinstance(files, list):
        return Response({
            "error": "Expected { files: string[] }"
        }, status=status.HTTP_400_BAD_REQUEST)

    base_dir = Path(settings.RECORDINGS_BASE_DIR)
    
    if not base_dir.exists():
        return Response({
            "error": f"Recordings directory does not exist: {base_dir}"
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    # Create temp workspace
    job_id = str(uuid.uuid4())
    tmp_root = Path(tempfile.gettempdir()) / f"recoverjob-{job_id}"
    input_dir = tmp_root / "input"
    output_dir = tmp_root / "output"
    
    try:
        input_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)
        
        staged_files = []

        # Stage files - copy to temp directory
        for filename in files:
            try:
                src = resolve_inside(base_dir, filename)
                if not src.exists() or not src.is_file():
                    raise ValueError(f"File not found: {filename}")
                dest = input_dir / Path(filename).name
                shutil.copy2(src, dest)
                staged_files.append(dest)
                logger.info(f"Staged file for recovery: {filename}")
            except Exception as e:
                shutil.rmtree(tmp_root, ignore_errors=True)
                logger.error(f"Error staging file {filename}: {e}")
                return Response({
                    "error": str(e)
                }, status=status.HTTP_400_BAD_REQUEST)
        
        # Run mcap recover on each file
        recovered_files = []
        
        for input_file in staged_files:
            output_filename = input_file.stem + "-recovered" + input_file.suffix
            output_file = output_dir / output_filename
            
            try:
                # mcap recover input.mcap -o output.mcap
                cmd = ["mcap", "recover", str(input_file), "-o", str(output_file)]
                
                logger.info(f"Running: {' '.join(cmd)}")
                
                proc = subprocess.run(
                    cmd,
                    cwd=str(tmp_root),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=300  # 5 minute timeout per file
                )
                
                if proc.returncode != 0:
                    error_msg = proc.stderr.decode('utf-8') or "Unknown error"
                    logger.error(f"mcap recover failed for {input_file.name}: {error_msg}")
                    # Continue with other files instead of failing completely
                    continue
                
                if output_file.exists():
                    recovered_files.append(output_file)
                    logger.info(f"Successfully recovered: {input_file.name} -> {output_filename}")
                    
            except subprocess.TimeoutExpired:
                logger.error(f"Timeout recovering {input_file.name}")
                continue
            except Exception as e:
                logger.error(f"Error recovering {input_file.name}: {e}")
                continue

        if not recovered_files:
            shutil.rmtree(tmp_root, ignore_errors=True)
            return Response({
                "error": "No MCAP files were successfully recovered"
            }, status=status.HTTP_400_BAD_REQUEST)

        # Create Zip archive
        zip_filename = f"recovered_{datetime.now().strftime('%Y-%m-%d_%H-%M-%S')}.zip"
        zip_path = tmp_root / zip_filename
        
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            for rf in recovered_files:
                zf.write(rf, arcname=rf.name)
                logger.info(f"Added to zip: {rf.name}")
                
        with open(zip_path, 'rb') as f:
            zip_data = f.read()
            
        # Cleanup
        shutil.rmtree(tmp_root, ignore_errors=True)
        
        logger.info(f"Created zip with {len(recovered_files)} recovered files")
        
        response = HttpResponse(zip_data, content_type='application/zip')
        response['Content-Disposition'] = f'attachment; filename="{zip_filename}"'
        response['X-Recovered-Count'] = str(len(recovered_files))
        return response

    except Exception as e:
        if tmp_root.exists():
            shutil.rmtree(tmp_root, ignore_errors=True)
        logger.error(f"Unexpected error in recover_and_zip: {e}")
        return Response({
            "error": str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
