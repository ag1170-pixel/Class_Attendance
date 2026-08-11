import urllib.request
import ssl
import os

url = 'https://raw.githubusercontent.com/tucan9389/FaceRecognition-in-CoreML/master/FaceRecognition/MobileFaceNet.mlmodel'
dest = 'ios/ClassAttendance/MobileFaceNet.mlmodel'

print("Downloading MobileFaceNet.mlmodel (this may take a minute)...")
try:
    ctx = ssl._create_unverified_context()
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, context=ctx) as response, open(dest, 'wb') as out_file:
        out_file.write(response.read())
    print("Download successful! The model is saved at:", dest)
    print("\nNext steps:")
    print("1. Open Xcode.")
    print("2. Drag the MobileFaceNet.mlmodel file from the Finder into your Xcode project sidebar (under ClassAttendance).")
    print("3. Check 'Copy items if needed'.")
    print("4. Check the target 'ClassAttendance'.")
except Exception as e:
    print("Download failed:", e)
    print("\nAlternative: Go to https://github.com/tucan9389/FaceRecognition-in-CoreML/blob/master/FaceRecognition/MobileFaceNet.mlmodel and click 'Download raw file', then drag it into Xcode.")
