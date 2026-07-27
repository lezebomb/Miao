export class CanvasRenderer {
  constructor(canvas, { width, height, edgeSmoothing = {} }) {
    this.canvas = canvas;
    this.width = width;
    this.height = height;
    this.edgeSmoothing = {
      enabled: edgeSmoothing.enabled !== false,
      blurPx: Number(edgeSmoothing.blurPx ?? 0.7),
      alpha: Number(edgeSmoothing.alpha ?? 0.24),
    };
    this.images = new Map();
    this.offscreen = document.createElement("canvas");
    this.resize();
    window.addEventListener("resize", () => this.resize());
  }

  resize() {
    this.pixelRatio = Math.max(1, window.devicePixelRatio || 1);
    this.canvas.width = Math.round(this.width * this.pixelRatio);
    this.canvas.height = Math.round(this.height * this.pixelRatio);
    this.offscreen.width = this.canvas.width;
    this.offscreen.height = this.canvas.height;
    this.canvas.style.width = "100%";
    this.canvas.style.height = "100%";
  }

  async preload(urls) {
    await Promise.all([...new Set(urls)].map((url) => this.loadImage(url)));
  }

  loadImage(url) {
    if (!this.images.has(url)) {
      this.images.set(
        url,
        new Promise((resolve, reject) => {
          const image = new Image();
          image.decoding = "async";
          image.onload = () => resolve(image);
          image.onerror = () => reject(new Error(`Unable to load animation frame: ${url}`));
          image.src = url;
        }),
      );
    }
    return this.images.get(url);
  }

  async render(frameUrl, transform) {
    const image = await this.loadImage(frameUrl);
    const ratio = this.pixelRatio;
    const buffer = this.offscreen.getContext("2d", { alpha: true });
    buffer.setTransform(1, 0, 0, 1, 0, 0);
    buffer.clearRect(0, 0, this.offscreen.width, this.offscreen.height);
    buffer.imageSmoothingEnabled = true;
    buffer.imageSmoothingQuality = "high";
    buffer.setTransform(ratio, 0, 0, ratio, 0, 0);
    buffer.drawImage(image, 0, 0, this.width, this.height);

    const context = this.canvas.getContext("2d", { alpha: true });
    context.setTransform(1, 0, 0, 1, 0, 0);
    context.clearRect(0, 0, this.canvas.width, this.canvas.height);
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = "high";
    context.save();
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.translate(
      this.width / 2 + transform.x,
      this.height / 2 + transform.y,
    );
    context.rotate((transform.rotation * Math.PI) / 180);
    context.scale(transform.scaleX, transform.scaleY);
    if (this.edgeSmoothing.enabled) {
      context.filter = `drop-shadow(0 0 ${this.edgeSmoothing.blurPx}px rgba(35, 22, 12, ${this.edgeSmoothing.alpha}))`;
    }
    context.drawImage(
      this.offscreen,
      -this.width / 2,
      -this.height / 2,
      this.width,
      this.height,
    );
    context.restore();
  }
}
