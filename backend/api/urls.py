from django.urls import path, include
from rest_framework.routers import DefaultRouter
from . import views

router = DefaultRouter()
router.register(r'files', views.MCAPFileViewSet)
router.register(r'synclogs', views.SyncLogViewSet)

urlpatterns = [
    path('', include(router.urls)),
    path('health/', views.health_check, name='health-check'),
    path('stats/', views.stats, name='stats'),
    path('sync/', views.trigger_sync, name='trigger-sync'),
]
