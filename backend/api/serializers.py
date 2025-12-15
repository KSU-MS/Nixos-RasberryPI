from rest_framework import serializers
from .models import MCAPFile, SyncLog


class MCAPFileSerializer(serializers.ModelSerializer):
    class Meta:
        model = MCAPFile
        fields = '__all__'


class SyncLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = SyncLog
        fields = '__all__'
