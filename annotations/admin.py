from django.contrib import admin
from .models import Annotation, AnnotationContext
# Register your models here.

@admin.register(AnnotationContext)
class AnnotationCotextAdmin(admin.ModelAdmin):
    list_dispaly = ('context_type', 'identifier', 'created_at')
    
@admin.register(Annotation)
class AnnotationAdmin(admin.ModelAdmin):
    list_display = ('annotation_type', 'context', 'user', 'created_at')