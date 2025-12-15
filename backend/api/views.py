import os
import subprocess
import hashlib
from pathlib import Path
from datetime import datetime

from django.conf import settings
from rest_framework import viewsets, status
from rest_framework.decorators import api_view, action
from rest_framework.response import Response

from .models import MCAPFile, SyncLog
from .serializers import MCAPFileSerializer, SyncLogSerializer


class MCAPFileViewSet(viewsets.ModelViewSet):
    """ViewSet for MCAP files."""
    queryset = MCAPFile.objects.all()
    serializer_class = MCAPFileSerializer

    @action(detail=False, methods=['get'])
    def scan(self, request):
        """Scan recordings directory and update database."""
        recordings_dir = Path(settings.RECORDINGS_DIR)
        
        if not recordings_dir.exists():
            return Response(
                {'error': f'Recordings directory not found: {recordings_dir}'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        found_files = []
        for mcap_file in recordings_dir.glob('**/*.mcap'):
            stat = mcap_file.stat()
            
            # Check if file already exists in DB
            db_file, created = MCAPFile.objects.update_or_create(
                filepath=str(mcap_file),
                defaults={
                    'filename': mcap_file.name,
                    'filesize': stat.st_size,
                }
            )
            found_files.append({
                'filename': mcap_file.name,
                'filepath': str(mcap_file),
                'filesize': stat.st_size,
                'created': created,
            })
        
        return Response({
            'scanned': len(found_files),
            'files': found_files,
        })

    @action(detail=True, methods=['get'])
    def info(self, request, pk=None):
        """Get MCAP file info using mcap-cli."""
        mcap_file = self.get_object()
        
        try:
            result = subprocess.run(
                ['mcap', 'info', mcap_file.filepath],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                return Response({
                    'filename': mcap_file.filename,
                    'info': result.stdout,
                })
            else:
                return Response(
                    {'error': result.stderr},
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR
                )
        except FileNotFoundError:
            return Response(
                {'error': 'mcap-cli not found'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
        except subprocess.TimeoutExpired:
            return Response(
                {'error': 'mcap info timed out'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class SyncLogViewSet(viewsets.ReadOnlyModelViewSet):
    """ViewSet for sync logs."""
    queryset = SyncLog.objects.all()
    serializer_class = SyncLogSerializer


@api_view(['GET'])
def health_check(request):
    """Health check endpoint."""
    return Response({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'recordings_dir': settings.RECORDINGS_DIR,
        'logs_dir': settings.LOGS_DIR,
    })


@api_view(['GET'])
def stats(request):
    """Get system stats."""
    recordings_dir = Path(settings.RECORDINGS_DIR)
    backup_dir = Path(settings.BACKUP_DIR)
    
    recordings_count = 0
    recordings_size = 0
    backup_count = 0
    backup_size = 0
    
    if recordings_dir.exists():
        for f in recordings_dir.glob('**/*.mcap'):
            recordings_count += 1
            recordings_size += f.stat().st_size
    
    if backup_dir.exists():
        for f in backup_dir.glob('**/*.mcap'):
            backup_count += 1
            backup_size += f.stat().st_size
    
    return Response({
        'recordings': {
            'count': recordings_count,
            'size_bytes': recordings_size,
            'size_human': _human_readable_size(recordings_size),
        },
        'backup': {
            'count': backup_count,
            'size_bytes': backup_size,
            'size_human': _human_readable_size(backup_size),
        },
        'database': {
            'mcap_files': MCAPFile.objects.count(),
            'sync_logs': SyncLog.objects.count(),
        }
    })


@api_view(['POST'])
def trigger_sync(request):
    """Manually trigger a sync operation."""
    try:
        result = subprocess.run(
            ['systemctl', 'start', 'mcap-sync.service'],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            return Response({'status': 'sync triggered'})
        else:
            return Response(
                {'error': result.stderr},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
    except Exception as e:
        return Response(
            {'error': str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )


def _human_readable_size(size_bytes):
    """Convert bytes to human readable string."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.2f} PB"
