# app/services/segment.py
# V4 NOTE: Segmentation is now handled by the Native Video Model (Gemini 2.5 Pro).

from typing import List, Tuple

def detect_action_segments(video_path: str) -> List[Tuple[float, float]]:
    """
    V4 STUB: This function is obsolete. Gemini generates the steps (segments).
    Returning mock data to prevent crashes if called by old dependencies.
    """
    print("WARNING: Calling obsolete segmentation module.")
    # Return a single large segment spanning the whole video (real steps come from Gemini)
    return [(0.0, 9999.0)]