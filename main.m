%% main.m - Batch run number plate pipeline on all images in Images/
% Saves intermediate outputs for debugging for each image.
% MODIFICATION INCLUDED:
%   1) Use horizontal rectangle dilation for better plate connectivity
%   2) Detect bounding box on morph pipeline as before
%   3) Crop plate ROI from GRAYSCALE image (imgray), then resize + adaptive binarize ROI

clc;
close all;
clear all;

% --- Paths / setup ---
rootDir   = fileparts(mfilename('fullpath'));
imagesDir = fullfile(rootDir, 'Batch-040603');
outRoot   = fullfile(rootDir, 'Batch-040603-Output');

if ~exist(outRoot, 'dir'), mkdir(outRoot); end

% Make sure required files are reachable
addpath(rootDir);
addpath(fullfile(rootDir, 'char'));

% If templates are required and not present, try generating them
templatesFile = fullfile(rootDir, 'NewTemplates.mat');
if ~exist(templatesFile, 'file') && exist(fullfile(rootDir,'create_templates.m'), 'file')
    fprintf('[INFO] NewTemplates.mat not found. Running create_templates.m ...\n');
    run(fullfile(rootDir,'create_templates.m'));
end

% Collect images
exts = {'*.jpg','*.jpeg','*.png','*.bmp','*.tif','*.tiff'};
files = [];
for k = 1:numel(exts)
    files = [files; dir(fullfile(imagesDir, exts{k}))]; %#ok<AGROW>
end

if isempty(files)
    error('No images found in folder: %s', imagesDir);
end

% Results accumulator
results = cell(numel(files), 3); % {filename, recognizedPlate, status}

% --- Process each image ---
for f = 1:numel(files)
    inFile = fullfile(files(f).folder, files(f).name);
    [~, baseName, ext] = fileparts(files(f).name);

    safeName = sanitizeName([baseName ext]);
    outDir   = fullfile(outRoot, safeName);
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, 'log.txt');
    fid = fopen(logFile, 'w');
    if fid < 0
        warning('Could not open log file for writing: %s', logFile);
        fid = [];
    end

    fprintf('=== Processing %s (%d/%d) ===\n', files(f).name, f, numel(files));
    logLine(fid, sprintf('Processing: %s', inFile));

    recognized = "";
    status = "OK";

    try
        % -----------------------
        % START OF PIPELINE
        % -----------------------

        % reads image
        im0 = imread(inFile);

        % resizes the image
        imRes = imresize(im0, [480 NaN]);
        saveImg(outDir, '01_original_resized.png', imRes);

        % converts to grayscale
        if ndims(imRes) == 3
            imgray = rgb2gray(imRes);
        else
            imgray = imRes;
        end
        saveImg(outDir, '02_gray.png', imgray);

        % binarizes the image (kept for debugging, but we now binarize plate ROI later)
        imbin_full = imbinarize(imgray);
        saveBin(outDir, '03_binarized_full.png', imbin_full);

        % edge detection using Sobel Algorithm
        imEdge = edge(imgray, 'sobel');
        saveBin(outDir, '04_edge_sobel.png', imEdge);

        % --- MODIFICATION #1: horizontal dilation (wide but short) ---
        se_horizontal = strel('rectangle', [4, 10]); % [height, width]
        imDil = imdilate(imEdge, se_horizontal);
        saveBin(outDir, '05_dilate_horizontal.png', imDil);

        % fills holes
        imFill = imfill(imDil, 'holes');
        saveBin(outDir, '06_fill_holes.png', imFill);

        % extract solid filled parts (trim fuzzy edges)
        imEro = imerode(imFill, strel('diamond', 2));
        saveBin(outDir, '07_erode_diamond2.png', imEro);

        % regionprops - added Extent to help filter non-rectangles
        Iprops = regionprops(imEro, 'BoundingBox', 'Area', 'Extent');
        if isempty(Iprops)
            status = "FAIL: no regions found after morphology";
            logLine(fid, char(status));
            results(f,:) = {files(f).name, "", char(status)};
            fcloseIf(fid);
            continue;
        end

        % --- MODIFICATION #2: filtering to pick plate-like candidate ---
        boundingBox = [];
        maxScore = 0;

        for i = 1:numel(Iprops)
            bb = Iprops(i).BoundingBox;
            area = Iprops(i).Area;
            w = bb(3);
            h = bb(4);
            aspectRatio = w / h;
            extent = Iprops(i).Extent;

            isLikelyPlate = (aspectRatio > 2.0 && aspectRatio < 7.0) && ...
                            (area > 1000 && area < 30000) && ...
                            (extent > 0.35);

            if isLikelyPlate
                if area > maxScore
                    maxScore = area;
                    boundingBox = bb;
                end
            end
        end

        % Fallback if strict filter fails
        if isempty(boundingBox)
            logLine(fid, '[WARN] Strict filter found no plate. Trying fallback...');
            maxFallback = 0;
            for i = 1:numel(Iprops)
                if Iprops(i).Area > maxFallback && Iprops(i).Area < 50000
                    maxFallback = Iprops(i).Area;
                    boundingBox = Iprops(i).BoundingBox;
                end
            end
        end

        % save overlay bbox on resized original
        saveBboxOverlay(outDir, '08_bbox_on_original.png', imRes, boundingBox);

        % -----------------------
        % MODIFICATION #3: crop from GRAYSCALE image (imgray), then binarize ROI
        % -----------------------
        if isempty(boundingBox)
            status = "FAIL: boundingBox empty (no plate candidate)";
            logLine(fid, char(status));
            results(f,:) = {files(f).name, "", char(status)};
            fcloseIf(fid);
            continue;
        end

        % Clamp bbox to image bounds (prevents empty crop)
        boundingBox = clampBbox(boundingBox, size(imgray));
        if isempty(boundingBox)
            status = "FAIL: bbox out of bounds after clamp";
            logLine(fid, char(status));
            results(f,:) = {files(f).name, "", char(status)};
            fcloseIf(fid);
            continue;
        end

        % Crop grayscale ROI
        imCropGray = imcrop(imgray, boundingBox);
        if isempty(imCropGray)
            status = "FAIL: gray crop returned empty (bbox out of range?)";
            logLine(fid, char(status));
            results(f,:) = {files(f).name, "", char(status)};
            fcloseIf(fid);
            continue;
        end
        saveImg(outDir, '09_plate_cropped_from_gray.png', imCropGray);

        % Resize grayscale plate ROI first
        imPlateGray = imresize(imCropGray, [240 NaN]);
        saveImg(outDir, '10_plate_gray_resized.png', imPlateGray);

        % Optional contrast boost
        imPlateGrayAdj = imadjust(imPlateGray);
        saveImg(outDir, '11_plate_gray_imadjust.png', imPlateGrayAdj);

        % Binarize ONLY the plate ROI (usually cleaner)
        imPlate = imbinarize(imPlateGrayAdj, 'adaptive', ...
            'ForegroundPolarity','dark', 'Sensitivity', 0.45);
        saveBin(outDir, '12_plate_binarized_from_gray_roi.png', imPlate);

        % -----------------------
        % REMAINDER OF PIPELINE (same logic, now uses imPlate instead of imCrop)
        % -----------------------

        % clear dust
        imOpen = imopen(imPlate, strel('rectangle', [4 4]));
        saveBin(outDir, '13_plate_open_rect4x4.png', imOpen);

        % remove some object if it's width is too long or too small than 500
        imChars = bwareaopen(~imOpen, 500);
        saveBin(outDir, '14_chars_bwareaopen_not_open_500.png', imChars);

        [h, w] = size(imChars); %#ok<NASGU>
        logLine(fid, sprintf('Chars mask size: %dx%d', size(imChars,1), size(imChars,2)));

        % Extract character regions
        Cprops = regionprops(imChars, 'BoundingBox', 'Area', 'Image');
        ccount = numel(Cprops);

        % save rectangle overlay on extracted chars
        saveCharBoxes(outDir, '15_chars_with_boxes.png', imChars, Cprops);

        % Read each letter (same logic / conditions)
        noPlate = "";
        for i = 1:ccount
            ow = size(Cprops(i).Image, 2);
            oh = size(Cprops(i).Image, 1);

            if ow < (h/2) && oh > (h/3)
                letter = readLetter(Cprops(i).Image);
                noPlate = noPlate + string(letter);

                % save each character crop
                charName = sprintf('char_%02d_%s.png', i, char(letter));
                saveBin(outDir, fullfile('chars', charName), Cprops(i).Image);
            end
        end

        recognized = noPlate;
        logLine(fid, sprintf('Recognized: %s', recognized));

        % Save final recognized plate text
        writeText(fullfile(outDir, 'recognized_plate.txt'), recognized);

        % Save a small summary mat for reproducibility
        save(fullfile(outDir, 'debug_workspace.mat'), ...
            'boundingBox', 'recognized', 'inFile', ...
            'imRes', 'imgray', 'imbin_full', 'imEdge', 'imDil', 'imFill', 'imEro', ...
            'imCropGray', 'imPlateGray', 'imPlateGrayAdj', 'imPlate', 'imOpen', 'imChars');

    catch ME
        status = "ERROR";
        recognized = "";
        logLine(fid, "Exception:");
        logLine(fid, ME.message);
        for s = 1:numel(ME.stack)
            logLine(fid, sprintf('  at %s (line %d)', ME.stack(s).name, ME.stack(s).line));
        end
        fprintf(2, '[ERROR] %s: %s\n', files(f).name, ME.message);
    end

    results(f,:) = {files(f).name, char(recognized), char(status)};
    fcloseIf(fid);

end

% Write batch results CSV
csvFile = fullfile(outRoot, 'batch_results.csv');
writeResultsCsv(csvFile, results);
fprintf('\nDone. Results saved to:\n  %s\n', csvFile);

%% ---------------- Local helper functions ----------------

function saveImg(outDir, relName, img)
    outPath = fullfile(outDir, relName);
    ensureParent(outPath);
    imwrite(img, outPath);
end

function saveBin(outDir, relName, bw)
    outPath = fullfile(outDir, relName);
    ensureParent(outPath);
    if islogical(bw)
        imwrite(uint8(bw) * 255, outPath);
    else
        imwrite(bw, outPath);
    end
end

function ensureParent(outPath)
    parent = fileparts(outPath);
    if ~exist(parent, 'dir')
        mkdir(parent);
    end
end

function saveBboxOverlay(outDir, fname, img, bbox)
    outPath = fullfile(outDir, fname);
    f = figure('Visible','off');
    imshow(img); title('Bounding Box on Original');
    hold on;
    if ~isempty(bbox)
        rectangle('Position', bbox, 'EdgeColor', 'g', 'LineWidth', 2);
    end
    hold off;
    exportgraphics(gca, outPath);
    close(f);
end

function saveCharBoxes(outDir, fname, bw, props)
    outPath = fullfile(outDir, fname);
    f = figure('Visible','off');
    imshow(bw); title('Extracted No. Plate with Isolated Character');
    hold on;
    [h, ~] = size(bw);
    for i = 1:numel(props)
        ow = size(props(i).Image, 2);
        oh = size(props(i).Image, 1);
        if ow < (h/2) && oh > (h/3)
            rectangle('Position', props(i).BoundingBox, 'EdgeColor', 'g', 'LineWidth', 2);
        end
    end
    hold off;
    exportgraphics(gca, outPath);
    close(f);
end

function writeText(path, txt)
    fid = fopen(path, 'w');
    if fid < 0, return; end
    fprintf(fid, '%s\n', txt);
    fclose(fid);
end

function writeResultsCsv(path, results)
    fid = fopen(path, 'w');
    if fid < 0, return; end
    fprintf(fid, 'filename,recognized_plate,status\n');
    for i = 1:size(results,1)
        fprintf(fid, '"%s","%s","%s"\n', ...
            escapeCsv(results{i,1}), escapeCsv(results{i,2}), escapeCsv(results{i,3}));
    end
    fclose(fid);
end

function s = escapeCsv(s)
    s = strrep(string(s), '"', '""');
    s = char(s);
end

function logLine(fid, msg)
    if isempty(fid) || fid < 0, return; end
    fprintf(fid, '[%s] %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'), msg);
end

function fcloseIf(fid)
    if ~isempty(fid) && fid > 0
        fclose(fid);
    end
end

function safe = sanitizeName(name)
    % Make folder names safe across OSes
    safe = regexprep(name, '[^\w\.-]', '_');
end

function bbox = clampBbox(bbox, imgSize)
    % bbox: [x y w h], imgSize: size(imgray) => [H W]
    H = imgSize(1);
    W = imgSize(2);

    x = max(1, floor(bbox(1)));
    y = max(1, floor(bbox(2)));
    w = max(1, ceil(bbox(3)));
    h = max(1, ceil(bbox(4)));

    if x > W || y > H
        bbox = [];
        return;
    end

    if x + w - 1 > W, w = W - x + 1; end
    if y + h - 1 > H, h = H - y + 1; end

    bbox = [x y w h];
end