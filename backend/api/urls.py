from django.urls import path
from . import views

urlpatterns = [
    path('files/', views.list_files, name='list_files'),
    path('recover-and-zip/', views.recover_and_zip, name='recover_and_zip'),
    path('health/', views.health_check, name='health_check'),
]
