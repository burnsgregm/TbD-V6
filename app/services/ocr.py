import cv2
import pytesseract
from typing import List, Tuple, Dict, Any, Optional

def _boxes_intersect(box1: List[int], box2: List[int]) -> bool:
    x1, y1, w1, h1 = box1
    x2, y2, w2, h2 = box2
    x_left = max(x1, x2)
    y_top = max(y1, y2)
    x_right = min(x1 + w1, x2 + w2)
    y_bottom = min(y1 + h1, y2 + h2)
    return not (x_right < x_left or y_bottom < y_top)

def run_ocr(frame: cv2.typing.MatLike, active_region: Optional[Tuple[int, int, int, int]] = None) -> List[Dict[str, Any]]:
    # Tesseract 5 is sufficient for finding the raw text bounding box
    ocr_data = pytesseract.image_to_data(frame, output_type=pytesseract.Output.DICT)
    results = []
    for i in range(len(ocr_data['text'])):
        text = ocr_data['text'][i].strip()
        try:
            conf_val = float(ocr_data['conf'][i])
        except:
            conf_val = 0.0
        confidence = conf_val / 100.0
        
        # V4 FIX: We MUST return all found text if we have no active_region filter.
        # The coordinate refinement logic in pipeline.py will match the text.
        if text: # We only filter out empty strings, keeping all confidence scores
            ui_region = [
                int(ocr_data['left'][i]), int(ocr_data['top'][i]),
                int(ocr_data['width'][i]), int(ocr_data['height'][i])
            ]
            
            # Since V4 Pipeline is doing refinement, we skip active_region filtering
            # and just return the raw results for the entire frame.
            results.append({"text": text, "confidence": confidence, "ui_region": ui_region})
            
    return results