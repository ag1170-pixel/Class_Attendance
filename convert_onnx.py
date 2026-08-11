import coremltools as ct
import onnx

# Load the SFace ONNX model
onnx_model_path = "recognition/models/face_recognition_sface_2021dec.onnx"
print(f"Loading ONNX model from {onnx_model_path}...")
onnx_model = onnx.load(onnx_model_path)

# Convert to CoreML
print("Converting to CoreML...")
# SFace input is typically 'input' with shape (1, 3, 112, 112)
# We can use ct.ImageType to make it accept an image directly!
image_input = ct.ImageType(name="input", shape=(1, 3, 112, 112), color_layout=ct.colorlayout.BGR)

mlmodel = ct.convert(
    onnx_model,
    inputs=[image_input],
    convert_to="neuralnetwork"
)

# Rename the output if necessary, or just save it
out_path = "ios/ClassAttendance/MobileFaceNet.mlmodel"
mlmodel.save(out_path)
print(f"Success! Model saved to {out_path}")
