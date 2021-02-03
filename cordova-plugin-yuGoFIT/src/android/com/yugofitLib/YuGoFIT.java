package com.yugofitLib;

import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.Image;
import android.os.Environment;
import android.os.Handler;
import android.util.Base64;
import android.util.Log;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.ImageCaptureException;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.core.impl.ImageAnalysisConfig;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.LifecycleOwner;

import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.android.gms.tasks.Task;
import com.google.common.util.concurrent.ListenableFuture;
import com.google.gson.Gson;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.pose.Pose;
import com.google.mlkit.vision.pose.PoseDetection;
import com.google.mlkit.vision.pose.PoseDetector;
import com.google.mlkit.vision.pose.PoseDetectorOptions;
import com.google.mlkit.vision.pose.PoseLandmark;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Executor;
import java.util.concurrent.Executors;

import com.yugofit.MainActivity;

import static org.apache.cordova.CordovaActivity.TAG;

public class YuGoFIT extends CordovaPlugin {
    private Executor executor = Executors.newSingleThreadExecutor();
    private int REQUEST_CODE_PERMISSIONS = 1001;
    private final String[] REQUIRED_PERMISSIONS = new String[]{"android.permission.CAMERA", /*"android.permission.WRITE_EXTERNAL_STORAGE"*/};

    CallbackContext cb;
    ImageProxy lastFrame;
    InputImage image;
    PreviewView mPreviewView;
    ImageView captureImage;
    private PoseDetector poseDetector;
    private ProcessCameraProvider cameraProvider;

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        if ("play".equals(action)) {
            play(callbackContext);
            return true;
        } else if ("stop".equals(action)) {
            stop(callbackContext);
            return true;
        } else if ("getLastFrame".equals(action)) {
            getLastFrame(callbackContext);
            return true;
        }

        return false;
    }

    private void getLastFrame(CallbackContext callbackContext) {
        String encodedImage = "";
        if (lastFrame != null) {
            @SuppressLint("UnsafeExperimentalUsageError")
            Bitmap bitmapImage = BitmapUtils.getBitmap(lastFrame);

            ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
            bitmapImage.compress(Bitmap.CompressFormat.JPEG, 50, byteArrayOutputStream);
            try {
                encodedImage = URLEncoder.encode(Base64.encodeToString(byteArrayOutputStream.toByteArray(), Base64.DEFAULT), "UTF-8");
            } catch (UnsupportedEncodingException e) {
                e.printStackTrace();
            }
        }

        callbackContext.success(encodedImage);
    }

    
    private void stop(CallbackContext callbackContext) {
        cb = null;
        if (cameraProvider != null) {
            cameraProvider.unbindAll();
        }
    }

    private void play(CallbackContext callbackContext) {
        cb = callbackContext;
        Context context = this.cordova.getActivity().getApplicationContext();
        mPreviewView = new PreviewView(context);
        mPreviewView.setLayoutParams(new FrameLayout.LayoutParams(0, 0));
        try{
            ((FrameLayout)webView.getView().getParent()).addView(mPreviewView);
        } catch (Exception e) {
            Log.d(TAG, "run: " + e.getLocalizedMessage());
            ((FrameLayout)webView.getView().getParent()).addView(mPreviewView);
        }
        if (allPermissionsGranted()) {
            startCamera(); //start camera if permission has been granted by user
        } else {
            ActivityCompat.requestPermissions(this.cordova.getActivity(), REQUIRED_PERMISSIONS, REQUEST_CODE_PERMISSIONS);
        }

        PoseDetectorOptions options =
                new PoseDetectorOptions.Builder()
                        .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
                        .setPerformanceMode(PoseDetectorOptions.PERFORMANCE_MODE_FAST)
                        .build();

        poseDetector = PoseDetection.getClient(options);

    }

    private void startCamera() {
        final ListenableFuture<ProcessCameraProvider> cameraProviderFuture = ProcessCameraProvider.getInstance(this.cordova.getActivity());

        cameraProviderFuture.addListener(new Runnable() {
            @Override
            public void run() {
                try {
                    cameraProvider = cameraProviderFuture.get();
                    bindPreview(cameraProvider);
                } catch (Exception e) {
                    Log.d(TAG, "run: " + e.getLocalizedMessage());
                    // No errors need to be handled for this Future.
                    // This should never be reached.
                }
            }
        }, ContextCompat.getMainExecutor(this.cordova.getActivity()));
    }

    void bindPreview(@NonNull ProcessCameraProvider cameraProvider) {
        Preview preview = new Preview.Builder()
                .build();

        CameraSelector cameraSelector = new CameraSelector.Builder()
                .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
                .build();

        ImageAnalysis imageAnalysis = new ImageAnalysis.Builder().build();
        imageAnalysis.setAnalyzer(Executors.newSingleThreadExecutor(), new ImageAnalysis.Analyzer() {
            @SuppressLint("UnsafeExperimentalUsageError")
            @Override
            public void analyze(@NonNull ImageProxy imageProxy) {
                lastFrame = imageProxy;
                @SuppressLint("UnsafeExperimentalUsageError")
                Image mediaImage = imageProxy.getImage();
                if (mediaImage != null) {
                    image = InputImage.fromMediaImage(lastFrame.getImage(), lastFrame.getImageInfo().getRotationDegrees());

                    // Pass image to an ML Kit Vision API
                    Task<Pose> result = poseDetector.process(image).addOnSuccessListener(
                            new OnSuccessListener<Pose>() {
                                @Override
                                public void onSuccess(Pose pose) {
                                    // Task completed successfully
                                    List<PoseLandmark> allPoseLandmarks = pose.getAllPoseLandmarks();
                                    Map<String, float[]> allPoseLandmarksMap = new HashMap<>();
                                    for (PoseLandmark poseLandmark : allPoseLandmarks) {
                                        // Log.d(TAG, String.format("Pose Landmark: %s, x=%.2f, y=%.2f", poseLandmark.getLandmarkType().name(),
                                        //         poseLandmark.getPosition().x, poseLandmark.getPosition().y));
                                        allPoseLandmarksMap.put(poseLandmark.getLandmarkType().name(), new float[]{poseLandmark.getPosition().x, poseLandmark.getPosition().y});
                                    }

                                    Gson gson = new Gson();
                                    String jsonString = gson.toJson(allPoseLandmarksMap);


                                    PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, jsonString);
                                    pluginResult.setKeepCallback(true);
                                    cb.sendPluginResult(pluginResult);
                                    //This is the json string

                                    imageProxy.close();
                                }
                            }).addOnFailureListener(
                            new OnFailureListener() {
                                @Override
                                public void onFailure(@NonNull Exception e) {
                                    // Task failed with an exception
                                    mediaImage.close();
                                }
                            });

                }
            }
        });


        ImageCapture.Builder builder = new ImageCapture.Builder();

        final ImageCapture imageCapture = builder
                .setTargetRotation(this.cordova.getActivity().getWindowManager().getDefaultDisplay().getRotation())
                .build();
        mPreviewView.setPreferredImplementationMode(PreviewView.ImplementationMode.SURFACE_VIEW);
        preview.setSurfaceProvider(mPreviewView.createSurfaceProvider());
        cameraProvider.unbindAll();
        Camera camera = cameraProvider.bindToLifecycle((LifecycleOwner) (this.cordova.getActivity()), cameraSelector, preview, imageAnalysis, imageCapture);
    }

    private boolean allPermissionsGranted() {
        for (String permission : REQUIRED_PERMISSIONS) {
            if (ContextCompat.checkSelfPermission(this.cordova.getActivity(), permission) != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
        }
        return true;
    }

    @Override
    public void onRequestPermissionResult(int requestCode, String[] permissions, int[] grantResults) throws JSONException {
        if (requestCode == REQUEST_CODE_PERMISSIONS) {
            if (allPermissionsGranted()) {
                startCamera();
            } else {
                Toast.makeText(this.cordova.getActivity(), "Permissions not granted by the user.", Toast.LENGTH_SHORT).show();
                this.cordova.getActivity().finish();
            }
        }
    }
}
