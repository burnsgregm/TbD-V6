import uvicorn
import os
from fastapi import FastAPI, HTTPException
from app.schema import TaskPayload

SERVICE_TYPE = os.environ.get("SERVICE_TYPE", "dispatcher")
app = FastAPI(title=f"TbD Engine V3 - {SERVICE_TYPE.upper()} Service")

if SERVICE_TYPE == "worker":
    try:
        from app.services.worker import WorkerService
        worker = WorkerService()
    except ImportError as e:
        print(f"CRITICAL: Failed to import WorkerService. Check dependencies. {e}")
        worker = None

    @app.post("/")
    async def pubsub_trigger(data: dict):
        if not worker:
            raise HTTPException(status_code=500, detail="Worker service failed to initialize.")
        try:
            # UPDATED: Await the worker
            await worker.process_pubsub_message(data)
            return {"status": "Processing initiated"}, 200
        except Exception as e:
            print(f"Worker processing failed: {e}")
            raise HTTPException(status_code=500, detail=f"Worker failure: {e}")

elif SERVICE_TYPE == "dispatcher":
    from app.services.dispatcher import DispatcherService
    dispatcher = DispatcherService()

    @app.post("/submit", status_code=202)
    async def submit_video_task(payload: TaskPayload):
        try:
            task_id = dispatcher.submit_task(payload)
            return {"status": "Task accepted and queued", "task_id": task_id}
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Dispatch failed: {e}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)