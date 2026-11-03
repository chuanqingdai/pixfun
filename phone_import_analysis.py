"""Queue local-only recognition after a verified browser import, off the HTTP thread."""
from agent_models import AgentCancelled


def schedule(library, agent, descriptions, shots, stopping, media_id):
    item, _ = library.get(media_id)
    if item['kind'] == 'video':
        descriptions.start(media_id)
        shots.start(media_id)
        return
    if item['kind'] != 'image': return
    library.patch(media_id, phoneImportAnalysis={'status':'queued','message':'Queued for local photo understanding'})
    def run():
        def progress(message):
            library.patch(media_id,phoneImportAnalysis={'status':'running','message':message})
        try:
            if stopping.is_set(): raise AgentCancelled()
            agent.observe({'mode':'local'},media_id,stopping,progress=progress)
            library.patch(media_id,phoneImportAnalysis={'status':'ready','message':''})
        except AgentCancelled:
            library.patch(media_id,phoneImportAnalysis={'status':'interrupted','message':'Local analysis interrupted. Imported files are kept.'})
        except Exception:
            library.patch(media_id,phoneImportAnalysis={'status':'failed','message':'Local photo analysis unavailable. Check the installed models. Imported files are kept.'})
    agent.pool.submit(run)
