from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from .models import Annotation, AnnotationContext
from html import unescape
import json

@csrf_exempt
def get_notes(request):
    context_identifier = request.GET.get('context', None)
    try:
        if context_identifier:
            # Filter annotations based on the related AnnotationContext identifier and order them
            annotations = Annotation.objects.filter(context__identifier=context_identifier).order_by('order')
        else:
            return JsonResponse({"error": "Context is required"}, status=400)

        # Serialize the annotations, decoding content to ensure proper rendering
        annotations_data = [
            {
                "id": annotation.id,
                "content": unescape(annotation.content.strip()),  # Decode HTML entities
                "annotation_type": annotation.annotation_type if hasattr(annotation, 'annotation_type') else None,
                "position": annotation.order,  # Use the order field for position
                "context": annotation.context.identifier,
            }
            for annotation in annotations
        ]
        return JsonResponse(annotations_data, safe=False)
    except Exception as e:
        return JsonResponse({"error": str(e)}, status=400)
    
# @csrf_exempt
# def update_all_notes(request):
#     if request.method == 'PUT':
#         try:
#             data = json.loads(request.body)
#             notes = data.get("notes", [])  # Expect HTML content
#             context_identifier = data.get("context", None)

#             if not context_identifier:
#                 return JsonResponse({"error": "Context is required"}, status=400)

#             # Get or create the related AnnotationContext object
#             annotation_context, created = AnnotationContext.objects.get_or_create(
#                 identifier=context_identifier
#             )

#             # Clear existing notes for the context
#             Annotation.objects.filter(context=annotation_context).delete()

#             # Create new notes with the correct order
#             for idx, content in enumerate(notes):
#                 if content.strip():  # Avoid saving empty notes
#                     decoded_content = unescape(content)  # Decode HTML entities before saving
#                     Annotation.objects.create(content=decoded_content, context=annotation_context, order=idx)

#             return JsonResponse({"status": "success"})
#         except Exception as e:
#             return JsonResponse({"error": str(e)}, status=400)

# @csrf_exempt
# def update_all_notes(request):
#     if request.method == 'PUT':
#         try:
#             data = json.loads(request.body)
#             notes = data.get("notes", [])  # Expect an array of notes
#             context_identifier = data.get("context", None)

#             if not context_identifier:
#                 return JsonResponse({"error": "Context is required"}, status=400)

#             # Get or create the related AnnotationContext object
#             annotation_context, created = AnnotationContext.objects.get_or_create(
#                 identifier=context_identifier
#             )

#             if not notes:  # If notes array is empty, delete the context
#                 annotation_context.delete()
#                 return JsonResponse({"status": f"Context '{context_identifier}' deleted successfully"})

#             # Clear existing notes for the context
#             Annotation.objects.filter(context=annotation_context).delete()

#             # Create new notes with the correct order, ignoring empty ones
#             for idx, content in enumerate(notes):
#                 content = content.strip()
#                 if content:  # Only save non-empty notes
#                     decoded_content = unescape(content)  # Decode HTML entities before saving
#                     Annotation.objects.create(content=decoded_content, context=annotation_context, order=idx)

#             return JsonResponse({"status": "success"})
#         except Exception as e:
#             return JsonResponse({"error": str(e)}, status=400)
@csrf_exempt
def update_all_notes(request):
    if request.method == 'PUT':
        try:
            data = json.loads(request.body)
            context_identifier = data.get("context", None)
            notes = data.get("notes", [])

            if not context_identifier:
                return JsonResponse({"error": "Context is required."}, status=400)

            # Get or create the AnnotationContext object
            annotation_context, created = AnnotationContext.objects.get_or_create(
                identifier=context_identifier
            )

            if not notes or all(note.strip() in ['', '<p><br/></p>'] for note in notes):
                # Delete the context if no valid notes are provided
                annotation_context.delete()
                return JsonResponse({"status": f"Context '{context_identifier}' deleted due to empty notes."})

            # Clear existing notes for the context
            Annotation.objects.filter(context=annotation_context).delete()

            # Save new notes with correct order
            for idx, content in enumerate(notes):
                content = content.strip()
                if content:  # Avoid saving empty notes
                    Annotation.objects.create(
                        content=unescape(content),  # Decode HTML entities before saving
                        context=annotation_context,
                        order=idx
                    )

            return JsonResponse({"status": "success", "message": f"Notes updated for context '{context_identifier}'."})
        except Exception as e:
            return JsonResponse({"error": str(e)}, status=500)
    else:
        return JsonResponse({"error": "Invalid HTTP method. Use PUT."}, status=405)
        
@csrf_exempt
def save_all_notes(request):
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            notes = data.get("notes", [])
            context_identifier = data.get("context", None)

            if not context_identifier:
                return JsonResponse({"error": "Context is required"}, status=400)

            # Get the related AnnotationContext object
            annotation_context = AnnotationContext.objects.filter(identifier=context_identifier).first()
            if not annotation_context:
                return JsonResponse({"error": f"Context '{context_identifier}' not found"}, status=404)

            # Clear existing notes for the context
            Annotation.objects.filter(context=annotation_context).delete()

            # Create new notes
            for content in notes:
                if content.strip():  # Avoid saving empty notes
                    Annotation.objects.create(content=content, context=annotation_context)

            return JsonResponse({"status": "success"})
        except Exception as e:
            return JsonResponse({"error": str(e)}, status=400)
        
@csrf_exempt
def get_all_notes(request):
    try:
        contexts = AnnotationContext.objects.all()
        all_notes = []
        for context in contexts:
            annotations = Annotation.objects.filter(context=context).order_by('order')
            notes = [
                {
                    "id": annotation.id,
                    "content": annotation.content.strip(),
                    "order": annotation.order,
                }
                for annotation in annotations
            ]
            all_notes.append({
                "context": context.identifier,
                "notes": notes,
            })
        return JsonResponse(all_notes, safe=False)
    except Exception as e:
        return JsonResponse({"error": str(e)}, status=400)
    
@csrf_exempt
def delete_note(request):
    if request.method == 'DELETE':
        try:
            data = json.loads(request.body)
            print(f"Received DELETE request with noteId: {data.get('noteId')}")
            
            note_id = data.get('noteId')

            if not note_id:
                return JsonResponse({"error": "Note ID is required."}, status=400)

            # Fetch and delete the note
            note = Annotation.objects.get(id=note_id)
            note.delete()
            return JsonResponse({"message": "Note deleted successfully."})
        except Annotation.DoesNotExist:
            return JsonResponse({"error": "Note not found."}, status=404)
        except Exception as e:
            return JsonResponse({"error": str(e)}, status=400)
    else:
        return JsonResponse({"error": "Invalid HTTP method."}, status=405)
    
@csrf_exempt
def delete_context(request):
    if request.method == 'DELETE':
        try:
            data = json.loads(request.body)
            context_identifier = data.get("context", None)

            if not context_identifier:
                return JsonResponse({"error": "Context is required."}, status=400)

            # Find and delete the context
            annotation_context = AnnotationContext.objects.filter(identifier=context_identifier).first()
            if annotation_context:
                annotation_context.delete()
                return JsonResponse({"message": f"Context '{context_identifier}' deleted successfully."})
            else:
                return JsonResponse({"error": f"Context '{context_identifier}' not found."}, status=404)
        except Exception as e:
            return JsonResponse({"error": str(e)}, status=500)
    else:
        return JsonResponse({"error": "Invalid HTTP method. Use DELETE."}, status=405)