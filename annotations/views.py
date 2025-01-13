from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
import json
from .models import Annotation, AnnotationContext

@csrf_exempt
def notes_view(request):
    if request.method == 'GET':
        context_identifier = request.GET.get('context')
        annotations = Annotation.objects.filter(context__identifier=context_identifier)
        notes = [{"id": a.id, "content": a.content} for a in annotations]
        return JsonResponse(notes, safe=False)

    elif request.method == 'POST':
        try:
            data = json.loads(request.body)
            print("Received POST data:", data)  # Debugging: Log incoming data
            if 'context' not in data or 'content' not in data:
                return JsonResponse({'error': 'Invalid data'}, status=400)
            context, _ = AnnotationContext.objects.get_or_create(identifier=data['context'])
            Annotation.objects.create(content=data['content'], context=context)
            return JsonResponse({'message': 'Note saved!'}, status=201)
        except Exception as e:
            print("Error in POST handler:", e)  # Debugging: Log the error
            return JsonResponse({'error': str(e)}, status=500)