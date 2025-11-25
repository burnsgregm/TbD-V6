import uuid
import os
import json
from google.cloud import pubsub_v1
from app.schema import TaskPayload

PUBSUB_TOPIC = "tb-d-ingest-tasks"
PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "local-dev-project")

class DispatcherService:
    def __init__(self):
        try:
            self.publisher = pubsub_v1.PublisherClient()
            self.topic_path = self.publisher.topic_path (PROJECT_ID, PUBSUB_TOPIC)
        except Exception as e:
            print(f"WARNING: Pub/Sub client failed to initialize: {e}")
            self.publisher = None

    def submit_task(self, payload: TaskPayload) -> str:
        if not payload.task_id:
            payload.task_id = str(uuid.uuid4())
        
        # V5 FR-02: Generate unique trace_id
        trace_id = str(uuid.uuid4())
        
        print(f"Dispatching Task ID: {payload.task_id}, Trace ID: {trace_id}")
        
        if self.publisher:
            data = json.dumps(payload.model_dump()).encode("utf-8")
            
            # V5 FR-02: Publish with trace_id attribute
            future = self.publisher.publish(
                self.topic_path, 
                data, 
                trace_id=trace_id, 
                task_id=payload.task_id # Adding task_id as attribute for audit visibility
            )
            print(f"Published to {self.topic_path}")
        else:
            print("MOCK PUBLISH: Pub/Sub not connected. Task would be queued here.")
            
        return payload.task_id