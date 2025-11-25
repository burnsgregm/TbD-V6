import pytesseract
try:
    print("Tesseract Version:", pytesseract.get_tesseract_version())
    print("OCR engine is accessible.")
except pytesseract.TesseractNotFoundError:
    print("ERROR: Tesseract is not installed or not in your system PATH.")
    print("Please manually install Tesseract using the Windows installer and update your PATH.")