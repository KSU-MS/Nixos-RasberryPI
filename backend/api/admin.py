from django.contrib import admin
from .models import MCAPFile, SyncLog


@admin.register(MCAPFile)
class MCAPFileAdmin(admin.ModelAdmin):
    list_display = ['filename', 'filesize', 'backed_up', 'created_at']
    list_filter = ['backed_up', 'created_at']
    search_fields = ['filename', 'filepath']


@admin.register(SyncLog)
class SyncLogAdmin(admin.ModelAdmin):
    list_display = ['id', 'status', 'files_synced', 'started_at', 'completed_at']
    list_filter = ['status', 'started_at']
