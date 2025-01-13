from django.urls import path
from .views import notes_view

urlpatterns = [
    path('api/notes', notes_view, name='notes_view'),
]