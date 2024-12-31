from django.db import models
from django.contrib.auth.models import User

# Create your models here.
class AnnotationContext(models.Model):
    """
    Stores the context where the annotation is applied.
    Example: Webpage URL, App window, or Document metadata.
    """
    CONTEXT_TYPES = [
        ('WEB', 'Webpage'),
        ('APP', 'Application'),
        ('DOC', 'Document')
    ]
    
    context_type = models.CharField(max_length=10, choices=CONTEXT_TYPES)
    identifier = models.TextField()  # e.g., URL, App name, or unique document ID
    created_at = models.DateTimeField(auto_now_add=True)
    
    def __str__(self):
        return f"{self.context_type} - {self.identifier}"
    
class Annotation(models.Model):
    """
    Represents an annotation made by the user.
    """
    ANNOTATION_TYPES = [
        ('TEXT', 'Text'),
        ('DRAW', 'Drawing'),
        ('IMG', 'Image'),
    ]
    
    annotation_type = models.CharField(max_length=10, choices=ANNOTATION_TYPES)
    content = models.TextField(blank=True, null=True) # For text annotations or drawing data
    image = models.ImageField(upload_to='annotations/', blank=True, null=True) # For image annotations
    position = models.JSONField() # Store position/coordinates (e.g., {'x': 100, 'y': 200})
    context = models.ForeignKey(AnnotationContext, on_delete=models.CASCADE, related_name="annotation")
    user = models.ForeignKey(User, on_delete=models.CASCADE, null=True, blank=True)  # Optional user association
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return f"{self.annotation_type} - {self.context.identifier}"