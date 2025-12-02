const admin = require('firebase-admin');

// Initialize without service account - will use gcloud auth
admin.initializeApp({
  storageBucket: 'retail-erp-dc742.firebasestorage.app'
});

async function setCors() {
  const bucket = admin.storage().bucket();

  const corsConfiguration = [
    {
      origin: ['*'],
      method: ['GET', 'HEAD', 'PUT', 'POST', 'DELETE'],
      maxAgeSeconds: 3600,
      responseHeader: ['Content-Type', 'Access-Control-Allow-Origin', 'x-goog-resumable']
    }
  ];

  try {
    await bucket.setCorsConfiguration(corsConfiguration);
    console.log('CORS configuration set successfully!');
  } catch (err) {
    console.error('Error setting CORS:', err.message);
    console.log('\n=== MANUAL STEPS TO FIX CORS ===');
    console.log('Go to Google Cloud Console:');
    console.log('https://console.cloud.google.com/storage/browser/retail-erp-dc742.firebasestorage.app');
    console.log('\n1. Click on bucket name');
    console.log('2. Click "Edit bucket settings" (pencil icon)');
    console.log('3. Scroll to "Cross-origin resource sharing (CORS)"');
    console.log('4. Click "ADD ITEM" and enter:');
    console.log('   - Origin: *');
    console.log('   - Method: GET, HEAD');
    console.log('   - Response header: Content-Type');
    console.log('   - Max age: 3600');
    console.log('5. Click Save\n');
  }
}

setCors();
