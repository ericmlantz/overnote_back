from django.views.decorators.csrf import csrf_exempt
from .models import Annotation, AnnotationContext
from html import unescape
import json
import requests
from django.http import JsonResponse
from bs4 import BeautifulSoup

def is_empty_html(html):
    if not html:
        return True
    cleaned = html.strip().replace('\n', '').replace(' ', '')
    return cleaned in ['', '<p><br></p>', '<p><br/></p>', '<p></p>']

@csrf_exempt
def get_notes(request):
    context_identifier = request.GET.get('context', None)
    # print(f"📥 Fetching notes for context: {context_identifier}")

    try:
        if context_identifier:
            annotations = Annotation.objects.filter(context__identifier=context_identifier).order_by('order')
            print(f"👀 Found {len(annotations)} notes for context '{context_identifier}'")

            annotations_data = [
                {
                    "id": annotation.id,
                    "content": unescape(annotation.content.strip()),
                    "context": annotation.context.identifier,
                }
                for annotation in annotations
            ]
            print(f"📨 Receiving notes for '{context_identifier}': {annotations_data}")
            return JsonResponse(annotations_data, safe=False)
        else:
            print("❌ Context is required")
            return JsonResponse({"error": "Context is required"}, status=400)
    except Exception as e:
        print(f"❌ Error fetching notes: {str(e)}")
        return JsonResponse({"error": str(e)}, status=400)
    
@csrf_exempt
def update_all_notes(request):
    if request.method == 'PUT':
        try:
            data = json.loads(request.body)
            context_identifier = data.get("context", None)
            notes = data.get("notes", [])

            print(f"📝 Received update request for context '{context_identifier}': {notes}")

            if not context_identifier:
                return JsonResponse({"error": "Context is required."}, status=400)

            # Get or create the AnnotationContext object
            annotation_context, created = AnnotationContext.objects.get_or_create(
                identifier=context_identifier
            )

            if not notes or all(is_empty_html(note) for note in notes):
                print(f"❌ Deleted context '{context_identifier}' due to empty notes from update.")
                Annotation.objects.filter(context=annotation_context).delete()
                annotation_context.delete()
                return JsonResponse({"status": f"Context '{context_identifier}' deleted due to empty notes."})

            # ✅ Prevent duplication: Clear existing notes before saving
            print(f"🔄 Clearing old notes for context '{context_identifier}'...")
            Annotation.objects.filter(context=annotation_context).delete()

            # Save new notes with correct order
            for idx, content in enumerate(notes):
                content = content.strip()
                if content:
                    Annotation.objects.create(
                        content=unescape(content),  # Decode HTML entities before saving
                        context=annotation_context,
                        order=idx
                    )

            print(f"✅ Notes updated successfully for context '{context_identifier}'")
            return JsonResponse({"status": "success", "message": f"Notes updated for context '{context_identifier}'."})
        except Exception as e:
            print(f"⛔️ Error saving notes: {str(e)}")
            return JsonResponse({"error": str(e)}, status=500)
        
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
            data = json.loads(request.body.decode("utf-8"))
            context_identifier = data.get("context", None)
            existing = AnnotationContext.objects.values_list('identifier', flat=True)
            if not context_identifier:
                return JsonResponse({"error": "Context is required."}, status=400)

            # Find and delete the context
            annotation_context = AnnotationContext.objects.filter(identifier=context_identifier).first()
            if annotation_context:
                annotation_context.delete()
                print(f"🗑 Context '{context_identifier}' has been deleted.")
                return JsonResponse({"message": f"Context '{context_identifier}' deleted successfully."})
            else:
                return JsonResponse({"status": "noop", "message": f"Context '{context_identifier}' did not exist."})
        except Exception as e:
            return JsonResponse({"error": str(e)}, status=500)
    else:
        return JsonResponse({"error": "Invalid HTTP method. Use DELETE."}, status=405)
    
@csrf_exempt
def get_page_title(request):
    url = request.GET.get('context', None)

    if not url:
        return JsonResponse({"error": "No URL provided"}, status=400)

    try:
        response = requests.get(url, timeout=5)
        soup = BeautifulSoup(response.text, 'html.parser')
        title = soup.title.string.strip() if soup.title else "Untitled Page"

        return JsonResponse({"title": title})
    except Exception as e:
        return JsonResponse({"error": f"Could not fetch title: {str(e)}"}, status=400)
