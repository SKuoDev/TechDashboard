const { createWorker } = require("tesseract.js");

const image = process.argv[2] || "IMG_0008.jpg";

(async () => {
  const worker = await createWorker("eng");
  const result = await worker.recognize(image);
  console.log(result.data.text);
  await worker.terminate();
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
