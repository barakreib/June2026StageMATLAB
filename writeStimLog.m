function outPath = writeStimLog(outDir, meta, header, data)
% writeStimLog  Write a stimulus log CSV with a fixed-width metadata preamble.
%
%   outPath = writeStimLog(outDir, meta, header, data)
%
%   The file is laid out so that EVERY row has exactly numel(header)
%   comma-separated fields. A reader can therefore skip the preamble and
%   parse numbers starting at the row given by the 'data_start_row'
%   metadata field:
%
%       rows 1 .. M      metadata:  key, value, <blank>, ... , <blank>
%       row  M+1         header  :  the column names in 'header'
%       rows M+2 ..      data    :  one numeric row per row of 'data'
%
%   A metadata key named 'data_start_row' is auto-filled with M+2 (the
%   1-indexed row of the first data row).
%
%   Inputs:
%     outDir : folder to write into (created if missing). Filename is
%              auto-generated as yyyy_mm_dd_NNNN.csv, where NNNN increments
%              past any file already present for today in outDir (so a trial
%              loop produces _0001, _0002, ... like the rig's convention).
%     meta   : K x 2 cell array {key, value}; value char/string or numeric.
%     header : 1 x C cell array of column-name strings.
%     data   : R x C numeric matrix (the data section).
%
%   Returns the full path of the file written.

    if nargin < 1 || isempty(outDir), outDir = pwd; end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    C = numel(header);

    % ---- Auto-generate filename yyyy_mm_dd_NNNN.csv (NNNN auto-increments) ----
    datePrefix = datestr(now, 'yyyy_mm_dd');
    existing   = dir(fullfile(outDir, [datePrefix '_*.csv']));
    nMax = 0;
    for i = 1:numel(existing)
        tok = regexp(existing(i).name, '_(\d+)\.csv$', 'tokens', 'once');
        if ~isempty(tok), nMax = max(nMax, str2double(tok{1})); end
    end
    outPath = fullfile(outDir, sprintf('%s_%04d.csv', datePrefix, nMax + 1));

    % ---- Auto-fill data_start_row = (#metadata rows) + 1 header + 1 ----
    dataStartRow = size(meta, 1) + 2;
    for i = 1:size(meta, 1)
        if strcmp(meta{i, 1}, 'data_start_row'), meta{i, 2} = dataStartRow; end
    end

    fid = fopen(outPath, 'w');
    if fid < 0, error('writeStimLog:cannotOpen', 'Cannot open %s for writing', outPath); end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>

    % ---- Metadata rows: key,value then C-2 empty fields (fixed width) ----
    tail = repmat(',', 1, C - 2);
    for i = 1:size(meta, 1)
        fprintf(fid, '%s,%s%s\n', local_str(meta{i, 1}), local_str(meta{i, 2}), tail);
    end

    % ---- Header row ----
    fprintf(fid, '%s\n', strjoin(header, ','));

    % ---- Data rows: single fprintf, column-major over data.' ----
    if ~isempty(data)
        fmt = [repmat('%.10g,', 1, C - 1), '%.10g\n'];
        fprintf(fid, fmt, data.');
    end
end

function s = local_str(x)
    if ischar(x)
        s = x;
    elseif isstring(x)
        s = char(x);
    else
        s = num2str(x, '%g');
    end
end
