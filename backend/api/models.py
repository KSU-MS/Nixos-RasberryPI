from django.db import models


class MCAPFile(models.Model):
    """Model to track MCAP files."""
    filename = models.CharField(max_length=255)
    filepath = models.CharField(max_length=1024)
    filesize = models.BigIntegerField(default=0)
    checksum = models.CharField(max_length=64, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    backed_up = models.BooleanField(default=False)
    backed_up_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.filename


class SyncLog(models.Model):
    """Model to track sync operations."""
    started_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(blank=True, null=True)
    files_synced = models.IntegerField(default=0)
    bytes_synced = models.BigIntegerField(default=0)
    status = models.CharField(max_length=50, default='running')
    error_message = models.TextField(blank=True, null=True)

    class Meta:
        ordering = ['-started_at']

    def __str__(self):
        return f"Sync {self.id} - {self.status}"
