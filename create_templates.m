% CREATE TEMPLATES
% This script reads character images, associates them with their 
% corresponding labels, and saves them into a unified structure.

clear; clc;

% Define the directory prefix
baseDir = 'char/';

% Define the mapping of Filenames to their actual Character Labels.
% Format: { 'Filename', 'CharacterLabel' }
fileMapping = {
    % Letters
    'A.bmp', 'A'; 'fillA.bmp', 'A';
    'B.bmp', 'B'; 'fillB.bmp', 'B';
    'C.bmp', 'C';
    'D.bmp', 'D'; 'fillD.bmp', 'D';
    'E.bmp', 'E'; 'F.bmp', 'F'; 'G.bmp', 'G'; 'H.bmp', 'H';
    'I.bmp', 'I'; 'J.bmp', 'J'; 'K.bmp', 'K'; 'L.bmp', 'L';
    'M.bmp', 'M'; 'N.bmp', 'N';
    'O.bmp', 'O'; 'fillO.bmp', 'O';
    'P.bmp', 'P'; 'fillP.bmp', 'P';
    'Q.bmp', 'Q'; 'fillQ.bmp', 'Q';
    'R.bmp', 'R'; 'fillR.bmp', 'R';
    'S.bmp', 'S'; 'T.bmp', 'T'; 'U.bmp', 'U'; 'V.bmp', 'V';
    'W.bmp', 'W'; 'X.bmp', 'X'; 'Y.bmp', 'Y'; 'Z.bmp', 'Z';
    
    % Numbers
    '1.bmp', '1'; '1_custom.bmp', '1'; % <--- ADDED THIS NEW TEMPLATE
    '2.bmp', '2'; '3.bmp', '3';
    '4.bmp', '4'; 'fill4.bmp', '4';
    '5.bmp', '5';
    '6.bmp', '6'; 'fill6.bmp', '6'; 'fill6_2.bmp', '6';
    '7.bmp', '7'; '7_custom.bmp', '7';
    '8.bmp', '8'; 'fill8.bmp', '8';
    '9.bmp', '9'; 'fill9.bmp', '9'; 'fill9_2.bmp', '9';
    '0.bmp', '0'; 'fill0.bmp', '0';
};

% Initialize the structure array
numTemplates = size(fileMapping, 1);
TemplateLibrary(numTemplates) = struct('Image', [], 'Label', '');

fprintf('Generating templates...\n');

for i = 1:numTemplates
    fileName = [baseDir fileMapping{i, 1}];
    label = fileMapping{i, 2};
    
    if exist(fileName, 'file')
        % Read the image
        img = imread(fileName);
        
        % Check if image is RGB, if so, convert to gray (robustness)
        if ndims(img) == 3
            img = rgb2gray(img);
        end
        
        % Convert to logical (binary) if not already
        if ~islogical(img)
            img = imbinarize(img);
        end

        % Store in structure
        TemplateLibrary(i).Image = img;
        TemplateLibrary(i).Label = label;
    else
        warning('File %s not found. Skipping.', fileName);
    end
end

% Save the structured library to a MAT file
save('NewTemplates.mat', 'TemplateLibrary');

fprintf('Successfully created "NewTemplates.mat" with %d templates.\n', numTemplates);