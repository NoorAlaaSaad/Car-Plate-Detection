function letter = readLetter(snap)
%READLETTER reads the character by comparing against TemplateLibrary.

    % Load the template library (persistent to speed up loops)
    persistent TemplateLibrary;
    if isempty(TemplateLibrary)
        load('NewTemplates.mat', 'TemplateLibrary');
    end

    % 1. Resize the input image to match template standard size
    snapResized = imresize(snap, [42 24]);
    % imwrite(snapResized, 'D_custom.bmp', 'bmp');


    % 2. Calculate Correlations
    numTemplates = length(TemplateLibrary);
    correlations = zeros(1, numTemplates);

    for n = 1:numTemplates
        correlations(n) = corr2(TemplateLibrary(n).Image, snapResized);
    end

    % 3. Find Best Match
    [maxScore, maxIndex] = max(correlations);
    letter = TemplateLibrary(maxIndex).Label;
    
    % Optional: Debugging Visualization
    % (Uncomment lines below if you want to see the live matching)
    
    % bestTemplate = TemplateLibrary(maxIndex).Image;
    % figure(99); 
    % set(gcf, 'Name', 'Character Recognition Debugger', 'NumberTitle', 'off');
    % subplot(1,3,1); imshow(snap); title('Original');
    % subplot(1,3,2); imshow(snapResized); title('Resized Input');
    % subplot(1,3,3); imshow(bestTemplate); 
    % title(sprintf('Matched: "%s"\nConf: %.2f%%', letter, maxScore*100), 'Color', 'g');
    % drawnow;
    % 
    % pause; % Uncomment this if you want to press a key to advance
end