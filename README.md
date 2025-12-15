# Automatic Number Plate Recognition (MATLAB)

Batch-process images to detect a license plate region, segment characters, and recognize the plate text using **template matching** (correlation against a template library).

This repo contains a small MATLAB ANPR pipeline:
- **Detection** via Sobel edges + morphology + region filtering
- **Plate ROI binarization** (adaptive thresholding on grayscale ROI)
- **Character segmentation** (connected components / `regionprops`)
- **Recognition** via `corr2` against templates stored in `NewTemplates.mat`

---

## Requirements

- **MATLAB** R2018b+ (older versions may work)
- **Image Processing Toolbox** (uses `imread`, `imresize`, `rgb2gray`, `edge`, `imdilate`, `imfill`, `imerode`, `imopen`, `bwareaopen`, `regionprops`, `imbinarize`, `corr2`, etc.)

---

## Project structure

Make sure your project folder looks like this:

```
project/
├─ main.m
├─ readLetter.m
├─ create_templates.m
├─ Images/                 # input images (jpg/png/bmp/tif...)
├─ char/                   # template character bitmaps (BMP)
│  ├─ A.bmp
│  ├─ ...
│  └─ 0.bmp
└─ NewTemplates.mat        # auto-generated if missing
```


---

## Quick start

1. Put your test images in the **`Images/`** folder.
2. Ensure your template BMPs are in **`char/`** (see next section).
3. In MATLAB, set the Current Folder to the project root and run:

```matlab
main.m
```

If `NewTemplates.mat` is missing, `main.m` will try to run `create_templates.m` automatically to generate it.

---

## Template library (NewTemplates.mat)

Character recognition happens in `readLetter.m` by comparing each segmented character to templates:

- Templates are loaded once (persistent variable) from **`NewTemplates.mat`**
- Each character image is resized to **42×24**
- The best match is picked by max correlation (`corr2`)

To (re)build the template library:

```matlab
create_templates.m
```

### Template mapping notes

`create_templates.m` contains a `fileMapping` table that maps a BMP filename to its label.

---

## Outputs

For each input image, the script creates a debug folder:

```
DebugOutputs/<image_name>/
├─ log.txt
├─ recognized_plate.txt
├─ 01_original_resized.png
├─ 02_gray.png
├─ ...
└─ chars/
   ├─ char_01_A.png
   ├─ char_02_7.png
   └─ ...
```

A batch summary CSV is also written:

- `DebugOutputs/batch_results.csv` with columns:
  - `filename`, `recognized_plate`, `status`

---

## How detection works (high level)

Inside `main.m`:

1. Resize image to height 480
2. Convert to grayscale
3. Sobel edges
4. **Horizontal dilation** (`strel('rectangle',[4,10])`) to connect plate strokes
5. Fill holes + erode to solidify regions
6. `regionprops` → pick best plate-like bounding box using:
   - aspect ratio
   - area bounds
   - extent (rectangularity)
7. Crop plate ROI from grayscale, resize, contrast-adjust, and **adaptive binarize**
8. Segment characters and recognize each one using `readLetter`

---

## Tuning tips

If plates are not detected well, adjust these in `main.m`:

- Dilation structuring element:
  ```matlab
  se_horizontal = strel('rectangle', [4, 10]);
  ```
- Region filter thresholds:
  - aspect ratio range (`2.0–7.0`)
  - area range (`1000–30000` / fallback `< 50000`)
  - extent threshold (`> 0.35`)
- Adaptive threshold sensitivity (plate ROI binarization):
  ```matlab
  imPlate = imbinarize(imPlateGrayAdj, 'adaptive', ...
      'ForegroundPolarity','dark', 'Sensitivity', 0.45);
  ```

If characters are missed/extra, tweak:

- `bwareaopen` threshold (`500`)
- the character selection heuristic:
  ```matlab
  if ow < (h/2) && oh > (h/3)
  ```

---
