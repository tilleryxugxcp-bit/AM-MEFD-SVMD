function generate_chapter4_analysis_outputs_schemeF(varargin)
%GENERATE_CHAPTER4_ANALYSIS_OUTPUTS_SCHEMEF Generate the Scheme F Chapter 4 analysis.
%
% This MATLAB version re-runs the AM-MEFD/SVMD algorithm from original XLSX
% files and exports figures for:
%   4.1 Burst-before/after multi-source time-history response
%   4.2 Vibration feature variation and measurement-point difference
%   4.3 Burst response time and operating-condition influence
%
% Usage:
%   generate_chapter4_analysis_outputs_schemeF
%   generate_chapter4_analysis_outputs_schemeF('Workers', 4)
%   generate_chapter4_analysis_outputs_schemeF('Root', 'F:\path\to\data')

cfg = parseConfig(varargin{:});
files = discoverXlsxFiles(cfg.root, cfg.outputDir);
if isempty(files)
    error('No XLSX files found under %s.', cfg.root);
end

fprintf('Found %d xlsx files\n', numel(files));
[detRows, featRows, errors] = processFiles(files, cfg);
if ~isempty(errors)
    fprintf('Warnings: %d files failed. Figures use successful files only.\n', numel(errors));
end
if isempty(detRows) || isempty(featRows)
    error('No successful AM-MEFD results; cannot draw figures.');
end

det = struct2table(detRows);
feat = struct2table(featRows);
det = sortrows(det, {'point','speed','opening','filename'});
feat = sortrows(feat, {'point','speed','opening','filename'});

cleanOutputDir(cfg.outputDir);
makeFigures(det, feat, cfg.outputDir, cfg);
exportChapter32FeatureTables(det, feat, cfg.outputDir, cfg);
exportChapter34FeatureTables(det, feat, cfg.outputDir);
fprintf('Done\nOutput directory: %s\n', cfg.outputDir);
end

function cfg = parseConfig(varargin)
p = inputParser;
p.addParameter('Root', pwd, @(x)ischar(x) || isstring(x));
p.addParameter('OutputDir', '', @(x)ischar(x) || isstring(x));
p.addParameter('Workers', 1, @(x)isnumeric(x) && isscalar(x));
p.addParameter('BaselineStart', 2.0, @isnumeric);
p.addParameter('BaselineEnd', 10.5, @isnumeric);
p.addParameter('DetectStart', 11.0, @isnumeric);
p.addParameter('DetectEnd', 15.5, @isnumeric);
p.addParameter('SegmentDuration', 5.0, @isnumeric);
p.addParameter('FinalStart', 20.0, @isnumeric);
p.addParameter('FinalEnd', 29.999, @isnumeric);
p.addParameter('UseSVMD', true, @(x)islogical(x) || isnumeric(x));
p.addParameter('SVMDNumIMFs', 4, @isnumeric);
p.addParameter('SVMDMaxIterations', 200, @isnumeric);
p.addParameter('SVMDPenaltyFactor', 1000, @isnumeric);
p.addParameter('SVMDMaxSamples', 2000, @isnumeric);
p.addParameter('TypicalSpeed', 40, @(x)isnumeric(x) && isscalar(x));
p.addParameter('TypicalOpening', 80, @(x)isnumeric(x) && isscalar(x));
p.addParameter('StrongCorrelationThreshold', 0.80, ...
    @(x)isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
p.addParameter('StrongCorrelationMinSamples', 20, ...
    @(x)isnumeric(x) && isscalar(x) && x >= 3);
p.addParameter('MaxSelectedFeaturesPerModality', 9, ...
    @(x)isnumeric(x) && isscalar(x) && x >= 2);
p.parse(varargin{:});
cfg = p.Results;
cfg.root = char(cfg.Root);
if strlength(string(cfg.OutputDir)) == 0
    cfg.outputDir = fullfile(cfg.root, 'outputs_am_mefd', 'chapter4_outputs_schemeF');
else
    cfg.outputDir = char(cfg.OutputDir);
end
cfg.workers = max(1, round(cfg.Workers));
cfg.baselineStart = cfg.BaselineStart;
cfg.baselineEnd = cfg.BaselineEnd;
cfg.detectStart = cfg.DetectStart;
cfg.detectEnd = cfg.DetectEnd;
cfg.segmentDuration = cfg.SegmentDuration;
cfg.finalStart = cfg.FinalStart;
cfg.finalEnd = cfg.FinalEnd;
cfg.useSVMD = logical(cfg.UseSVMD);
cfg.svmdNumIMFs = max(2, round(cfg.SVMDNumIMFs));
cfg.svmdMaxIterations = max(20, round(cfg.SVMDMaxIterations));
cfg.svmdPenaltyFactor = cfg.SVMDPenaltyFactor;
cfg.svmdMaxSamples = max(256, round(cfg.SVMDMaxSamples));
cfg.typicalSpeed = cfg.TypicalSpeed;
cfg.typicalOpening = cfg.TypicalOpening;
cfg.strongCorrelationThreshold = cfg.StrongCorrelationThreshold;
cfg.strongCorrelationMinSamples = round(cfg.StrongCorrelationMinSamples);
cfg.maxSelectedFeaturesPerModality = round(cfg.MaxSelectedFeaturesPerModality);
cfg.windowSec = 0.20;
cfg.frequencyWindowSec = 1.00;
cfg.stepSec = 0.05;
cfg.smoothSec = 0.05;
cfg.thresholdK = 6.0;
cfg.minPressureDropPct = 5.0;
cfg.consecutiveWindows = 3;
end

function files = discoverXlsxFiles(rootDir, outputDir)
listing = dir(fullfile(rootDir, '**', '*.xlsx'));
files = strings(0, 1);
for i = 1:numel(listing)
    if startsWith(listing(i).name, '~$')
        continue;
    end
    f = fullfile(listing(i).folder, listing(i).name);
    if contains(lower(f), lower(outputDir)) || contains(lower(f), lower(fullfile(rootDir, 'outputs_'))) || contains(lower(f), lower(fullfile(rootDir, 'tmp_')))
        continue;
    end
    files(end+1, 1) = string(f); %#ok<AGROW>
end
files = sort(files);
end

function [detRows, featRows, errors] = processFiles(files, cfg)
detRows = struct([]);
featRows = struct([]);
errors = struct([]);
for i = 1:numel(files)
    filePath = char(files(i));
    [folderPath, name, ext] = fileparts(filePath);
    [~, pointName] = fileparts(folderPath);
    fprintf('[%d/%d] processing %s/%s%s\n', i, numel(files), pointName, name, ext);
    try
        [drow, frow] = processOneFile(filePath, cfg);
        detRows = appendStruct(detRows, drow);
        featRows = appendStruct(featRows, frow);
    catch ME
        er.file_path = string(filePath);
        er.error = string(ME.message);
        errors = appendStruct(errors, er);
        fprintf('  failed: %s\n', ME.message);
    end
end
end

function arr = appendStruct(arr, item)
if isempty(arr)
    arr = item;
else
    arr(end+1) = item; %#ok<AGROW>
end
end

function [detRow, featRow] = processOneFile(filePath, cfg)
[folderPath, filename, ext] = fileparts(filePath);
[~, pointName] = fileparts(folderPath);
filename = [filename ext];
[speed, opening] = parseCondition(filename);
raw = readRawXlsx(filePath);
fs = estimateFs(raw.time);
df = addCompositeSignals(raw, cfg, fs);
det = identifyBoundary(df, cfg, fs);
feat = extractFeatures(df, det, fs);

base.point = string(pointName);
base.filename = string(filename);
base.file_path = string(filePath);
base.speed = speed;
base.opening = opening;
base.fs = fs;
base.rows = height(df);
base.time_start = min(df.time);
base.time_end = max(df.time);
detRow = mergeStructs(base, det);
featRow = mergeStructs(base, struct('burst_time', det.burst_time));
featRow = mergeStructs(featRow, feat);
end

function out = mergeStructs(a, b)
out = a;
fields = fieldnames(b);
for k = 1:numel(fields)
    out.(fields{k}) = b.(fields{k});
end
end

function [speed, opening] = parseCondition(filename)
tok = regexp(filename, '^(\d+)-(\d+)', 'tokens', 'once');
if isempty(tok)
    speed = NaN; opening = NaN; return;
end
speed = str2double(tok{1});
code = str2double(tok{2});
switch code
    case 4, opening = 40;
    case 6, opening = 60;
    case 8, opening = 80;
    case 10, opening = 100;
    otherwise, opening = code * 10;
end
end

function tbl = readRawXlsx(filePath)
mat = readmatrix(filePath, 'NumHeaderLines', 4);
mat = mat(:, 1:min(12, size(mat, 2)));
if size(mat, 2) < 12
    error('Expected at least 12 numeric columns, got %d.', size(mat, 2));
end
mat = mat(all(~isnan(mat(:, 1)), 2), :);
tbl = array2table(mat(:, 1:12), 'VariableNames', {'time','pressure_1','pressure_2','pressure_3','pressure_4','pressure_5','pressure_6','pressure_7','pressure_8','flow','vibration_1','vibration_2'});
end

function fs = estimateFs(time)
d = diff(time(isfinite(time)));
d = d(d > 0 & isfinite(d));
if isempty(d)
    fs = 1000;
else
    fs = 1 / median(d);
end
end

function df = addCompositeSignals(df, cfg, fs)
pressure = df{:, {'pressure_1','pressure_2','pressure_3','pressure_4','pressure_5','pressure_6','pressure_7','pressure_8'}};
df.pressure_mean = mean(pressure, 2, 'omitnan');
smoothN = max(3, round(cfg.smoothSec * fs));
if mod(smoothN, 2) == 0
    smoothN = smoothN + 1;
end
df.pressure_mean_smooth = movmedian(df.pressure_mean, smoothN, 'omitnan');
df.flow_smooth = movmedian(df.flow, smoothN, 'omitnan');
df.vibration_1_smooth = movmedian(df.vibration_1, smoothN, 'omitnan');
df.vibration_2_smooth = movmedian(df.vibration_2, smoothN, 'omitnan');
df.svmd_energy = computeSvmdEnergy(df, cfg);
end

function energy = computeSvmdEnergy(df, cfg)
energy = zeros(height(df), 1);
if ~isfield(cfg, 'useSVMD') || ~cfg.useSVMD || exist('vmd', 'file') ~= 2
    return;
end
idx = df.time >= cfg.baselineStart & df.time <= cfg.detectEnd;
if nnz(idx) < 64
    return;
end
pressureComponent = svmdEnergyComponent(df.pressure_mean_smooth(idx), cfg);
vibrationSignal = sqrt(df.vibration_1_smooth(idx).^2 + df.vibration_2_smooth(idx).^2);
vibrationComponent = svmdEnergyComponent(vibrationSignal, cfg);
combined = normalizeVector(pressureComponent) + normalizeVector(vibrationComponent);
energy(idx) = combined;
end

function e = svmdEnergyComponent(x, cfg)
x = x(:);
nOriginal = numel(x);
x = fillmissing(x, 'linear', 'EndValues', 'nearest');
if nOriginal > cfg.svmdMaxSamples
    sampleIdx = unique(round(linspace(1, nOriginal, cfg.svmdMaxSamples))).';
    xWork = x(sampleIdx);
else
    sampleIdx = (1:nOriginal).';
    xWork = x;
end
s = std(xWork, 'omitnan');
if ~isfinite(s) || s <= 1e-12
    e = zeros(nOriginal, 1);
    return;
end
xWork = (xWork - mean(xWork, 'omitnan')) ./ s;
try
    imf = svmdLocal(xWork, cfg);
    if size(imf, 1) ~= numel(xWork) && size(imf, 2) == numel(xWork)
        imf = imf.';
    end
    disturbance = imf;
    eWork = sum(disturbance.^2, 2, 'omitnan');
    eWork = movmean(eWork, 25, 'omitnan');
    if numel(eWork) == nOriginal
        e = eWork(:);
    else
        e = interp1(sampleIdx, eWork(:), (1:nOriginal).', 'linear', 'extrap');
    end
catch
    e = zeros(nOriginal, 1);
end
e(~isfinite(e)) = 0;
end

function modes = svmdLocal(x, cfg)
%SVMDLOCAL Successive mode extraction using variational mode subproblems.
x = x(:);
residual = x;
numModes = max(1, cfg.svmdNumIMFs - 1);
modes = zeros(numel(x), numModes);
for k = 1:numModes
    if std(residual, 'omitnan') <= 1e-10
        modes = modes(:, 1:max(k-1, 1));
        break;
    end
    pair = vmd(residual, NumIMFs=2, MaxIterations=cfg.svmdMaxIterations, PenaltyFactor=cfg.svmdPenaltyFactor, Display=false);
    if size(pair, 1) ~= numel(residual) && size(pair, 2) == numel(residual)
        pair = pair.';
    end
    if size(pair, 2) < 2
        mode = pair(:, 1);
    else
        c1 = spectralCentroidForMode(pair(:, 1));
        c2 = spectralCentroidForMode(pair(:, 2));
        if c1 >= c2
            mode = pair(:, 1);
        else
            mode = pair(:, 2);
        end
    end
    modes(:, k) = mode;
    residual = residual - mode;
end
if size(modes, 2) < cfg.svmdNumIMFs
    modes(:, end+1) = residual;
end
end

function c = spectralCentroidForMode(x)
x = x(:) - mean(x, 'omitnan');
p = abs(fft(x)).^2;
n = numel(x);
keep = 1:floor(n/2)+1;
p = p(keep);
f = (keep - 1)';
p(1) = 0;
total = sum(p, 'omitnan');
if total <= 1e-20
    c = 0;
else
    c = sum(f .* p, 'omitnan') / total;
end
end
function y = normalizeVector(x)
x = x(:);
lo = min(x, [], 'omitnan');
hi = max(x, [], 'omitnan');
if ~isfinite(lo) || ~isfinite(hi) || abs(hi - lo) < 1e-12
    y = zeros(size(x));
else
    y = (x - lo) ./ (hi - lo);
end
y(~isfinite(y)) = 0;
end

function wt = windowTable(df, cfg, fs)
t = df.time;
p = df.pressure_mean_smooth;
f = df.flow_smooth;
v1 = df.vibration_1_smooth;
v2 = df.vibration_2_smooth;
ve = df.svmd_energy;
dpdt = gradient(p, t);
starts = cfg.baselineStart:cfg.stepSec:(cfg.detectEnd - cfg.windowSec);
rows = [];
for startT = starts
    endT = startT + cfg.windowSec;
    mask = t >= startT & t < endT;
    if nnz(mask) < max(10, round(0.25 * cfg.windowSec * fs))
        continue;
    end
    row.window_start = startT;
    row.window_end = endT;
    row.pressure_mean = mean(p(mask), 'omitnan');
    row.pressure_grad_min = min(dpdt(mask), [], 'omitnan');
    row.flow_mean = mean(f(mask), 'omitnan');
    row.vib_energy = mean(v1(mask).^2 + v2(mask).^2, 'omitnan');
    row.svmd_energy = mean(ve(mask), 'omitnan');
    rows = appendStruct(rows, row);
end
wt = struct2table(rows);
end

function det = identifyBoundary(df, cfg, fs)
wt = windowTable(df, cfg, fs);
base = wt(wt.window_start >= cfg.baselineStart & wt.window_end <= cfg.baselineEnd, :);
cand = wt(wt.window_start >= cfg.detectStart & wt.window_start <= cfg.detectEnd, :);
if isempty(base) || isempty(cand)
    error('Baseline or detection window is empty.');
end
basePressure = median(base.pressure_mean, 'omitnan');
baseFlow = median(base.flow_mean, 'omitnan');
baseVibEnergy = median(base.vib_energy, 'omitnan');
baseSvmdEnergy = median(base.svmd_energy, 'omitnan');
pressureScale = max([robustMad(base.pressure_mean), abs(basePressure) * 0.005, 1e-12]);
gradScale = max([robustMad(base.pressure_grad_min), 1e-12]);
flowScale = max([robustMad(base.flow_mean), abs(baseFlow) * 0.002, 1e-12]);
vibScale = max([robustMad(base.vib_energy), abs(baseVibEnergy) * 0.01, 1e-12]);
svmdScale = max([robustMad(base.svmd_energy), abs(baseSvmdEnergy) * 0.01, 1e-12]);

wt.pressure_drop_z = max(0, (basePressure - wt.pressure_mean) ./ pressureScale);
wt.pressure_grad_z = max(0, (median(base.pressure_grad_min, 'omitnan') - wt.pressure_grad_min) ./ gradScale);
wt.flow_change_z = max(0, abs(wt.flow_mean - baseFlow) ./ flowScale);
wt.vib_energy_z = max(0, (wt.vib_energy - baseVibEnergy) ./ vibScale);
wt.svmd_energy_z = max(0, (wt.svmd_energy - baseSvmdEnergy) ./ svmdScale);
wt.transition_index = 0.32 * wt.pressure_drop_z + 0.20 * wt.pressure_grad_z + 0.08 * wt.flow_change_z + 0.20 * wt.vib_energy_z + 0.20 * wt.svmd_energy_z;
baseIdx = wt.transition_index(wt.window_start >= cfg.baselineStart & wt.window_end <= cfg.baselineEnd);
threshold = median(baseIdx, 'omitnan') + cfg.thresholdK * max(robustMad(baseIdx), 1e-12);
threshold = max(threshold, 3.0);

cand = wt(wt.window_start >= cfg.detectStart & wt.window_start <= cfg.detectEnd, :);
cand.pressure_drop_pct_window = (basePressure - cand.pressure_mean) ./ max(abs(basePressure), 1e-12) * 100;
cand.hit = cand.transition_index >= threshold & cand.pressure_drop_pct_window >= cfg.minPressureDropPct;
burstTime = NaN;
for i = 1:(height(cand) - cfg.consecutiveWindows + 1)
    if all(cand.hit(i:i+cfg.consecutiveWindows-1))
        burstTime = cand.window_start(i);
        break;
    end
end
if ~isfinite(burstTime)
    [~, bestIdx] = max(cand.transition_index + 0.01 * cand.pressure_drop_pct_window);
    burstTime = cand.window_start(bestIdx);
end

t = df.time;
p = df.pressure_mean_smooth;
localMask = t >= burstTime - 0.30 & t <= burstTime + 0.50;
if nnz(localMask) >= 5
    localT = t(localMask);
    localP = p(localMask);
    localGrad = gradient(localP, localT);
    [~, idx] = min(localGrad);
    burstTime = localT(idx);
end

preMask = t >= max(cfg.baselineStart, burstTime - 2.0) & t < burstTime - 0.2;
transientMask = t >= burstTime + 0.5 & t < min(max(t), burstTime + cfg.segmentDuration);
finalStart = min(max(cfg.finalStart, burstTime + cfg.segmentDuration), max(t));
finalEnd = min(cfg.finalEnd, max(t));
finalMask = t >= finalStart & t <= finalEnd;
if nnz(preMask) < 10
    preMask = t >= cfg.baselineStart & t <= cfg.baselineEnd;
end
if nnz(transientMask) < 10
    transientMask = t >= burstTime;
end
if nnz(finalMask) < 10
    finalMask = t >= max(burstTime + cfg.segmentDuration, burstTime);
end
steadyPressure = mean(df.pressure_mean(preMask), 'omitnan');
transientPressure = mean(df.pressure_mean(transientMask), 'omitnan');
finalPressure = mean(df.pressure_mean(finalMask), 'omitnan');
steadyFlow = mean(df.flow(preMask), 'omitnan');
transientFlow = mean(df.flow(transientMask), 'omitnan');
finalFlow = mean(df.flow(finalMask), 'omitnan');
[~, bestRow] = min(abs(wt.window_start - burstTime));

det.burst_time = burstTime;
det.burst_index = find(abs(t - burstTime) == min(abs(t - burstTime)), 1) - 1;
det.steady_start = cfg.baselineStart;
det.steady_end = burstTime;
det.nonstationary_start = burstTime;
det.nonstationary_end = min(max(t), burstTime + cfg.segmentDuration);
det.final_start = finalStart;
det.final_end = finalEnd;
det.steady_pressure = steadyPressure;
det.transient_pressure = transientPressure;
det.final_pressure = finalPressure;
det.transient_pressure_drop_pct = (steadyPressure - transientPressure) / max(abs(steadyPressure), 1e-12) * 100;
det.final_pressure_drop_pct = (steadyPressure - finalPressure) / max(abs(steadyPressure), 1e-12) * 100;
det.pressure_drop_pct = det.final_pressure_drop_pct;
det.steady_flow = steadyFlow;
det.transient_flow = transientFlow;
det.final_flow = finalFlow;
det.transient_flow_increase_pct = (transientFlow - steadyFlow) / max(abs(steadyFlow), 1e-12) * 100;
det.final_flow_increase_pct = (finalFlow - steadyFlow) / max(abs(steadyFlow), 1e-12) * 100;
det.flow_increase_pct = det.final_flow_increase_pct;
det.transition_index = wt.transition_index(bestRow);
det.threshold = threshold;
det.baseline_pressure = basePressure;
det.baseline_flow = baseFlow;
det.baseline_vib_energy = baseVibEnergy;
det.baseline_svmd_energy = baseSvmdEnergy;
det.svmd_energy_index = wt.svmd_energy_z(bestRow);
end

function m = robustMad(x)
x = x(isfinite(x));
if isempty(x)
    m = 0;
else
    med = median(x, 'omitnan');
    m = 1.4826 * median(abs(x - med), 'omitnan');
end
end

function feat = extractFeatures(df, det, fs)
seg = df(df.time >= det.nonstationary_start & df.time <= det.nonstationary_end, :);
if isempty(seg)
    error('Nonstationary segment is empty.');
end
feat.segment_start = det.nonstationary_start;
feat.segment_end = det.nonstationary_end;
feat.segment_duration = det.nonstationary_end - det.nonstationary_start;
feat.segment_rows = height(seg);
fields = {'pressure_mean','flow','vibration_1','vibration_2'};
for i = 1:numel(fields)
    feat = mergeStructs(feat, channelFeatures(fields{i}, seg.(fields{i}), fs));
end
vibEnergy = seg.vibration_1.^2 + seg.vibration_2.^2;
feat = mergeStructs(feat, channelFeatures('vibration_combined_energy', vibEnergy, fs));
feat.svmd_energy_mean = mean(seg.svmd_energy, 'omitnan');
feat.svmd_energy_std = std(seg.svmd_energy, 'omitnan');
feat.svmd_energy_max = max(seg.svmd_energy, [], 'omitnan');
feat.svmd_energy_rms = sqrt(mean(seg.svmd_energy.^2, 'omitnan'));
feat.svmd_energy_total = sum(seg.svmd_energy, 'omitnan');
end

function out = channelFeatures(prefix, x, fs)
x = x(isfinite(x));
out.([prefix '_mean']) = mean(x, 'omitnan');
out.([prefix '_std']) = std(x, 'omitnan');
out.([prefix '_min']) = min(x, [], 'omitnan');
out.([prefix '_max']) = max(x, [], 'omitnan');
out.([prefix '_ptp']) = max(x, [], 'omitnan') - min(x, [], 'omitnan');
out.([prefix '_rms']) = sqrt(mean(x.^2, 'omitnan'));
out.([prefix '_energy']) = sum(x.^2, 'omitnan');
out.([prefix '_skewness']) = skewnessLocal(x);
out.([prefix '_kurtosis']) = kurtosisLocal(x);
out.([prefix '_zcr']) = zeroCrossingRate(x);
out.([prefix '_perm_entropy']) = permutationEntropyLocal(x);
spec = spectralFeatures(x, fs);
keys = fieldnames(spec);
for i = 1:numel(keys)
    out.([prefix '_' keys{i}]) = spec.(keys{i});
end
end

function s = skewnessLocal(x)
if numel(x) < 3 || std(x, 'omitnan') <= 1e-12
    s = 0;
else
    z = (x - mean(x, 'omitnan')) ./ std(x, 'omitnan');
    s = mean(z.^3, 'omitnan');
end
end

function k = kurtosisLocal(x)
if numel(x) < 4 || std(x, 'omitnan') <= 1e-12
    k = 0;
else
    z = (x - mean(x, 'omitnan')) ./ std(x, 'omitnan');
    k = mean(z.^4, 'omitnan');
end
end

function zcr = zeroCrossingRate(x)
if numel(x) < 2
    zcr = NaN;
else
    y = x - mean(x, 'omitnan');
    zcr = mean(y(2:end) .* y(1:end-1) < 0, 'omitnan');
end
end

function pe = permutationEntropyLocal(x)
x = x(isfinite(x));
order = 3;
if numel(x) < order + 1
    pe = NaN; return;
end
patterns = zeros(max(numel(x) - order + 1, 0), order);
for i = 1:size(patterns, 1)
    [~, idx] = sort(x(i:i+order-1));
    patterns(i, :) = idx;
end
[~, ~, ic] = unique(patterns, 'rows');
counts = accumarray(ic, 1);
prob = counts ./ sum(counts);
pe = -sum(prob .* log(prob + 1e-20)) / log(factorial(order));
end

function spec = spectralFeatures(x, fs)
x = x(isfinite(x));
if numel(x) < 8 || fs <= 0
    spec = struct('dominant_freq', NaN, 'spectral_centroid', NaN, 'low_band_energy', NaN, 'mid_band_energy', NaN, 'high_band_energy', NaN, 'high_band_ratio', NaN);
    return;
end
y = x - mean(x, 'omitnan');
pow = abs(fft(y)).^2;
n = numel(y);
keep = 1:floor(n/2)+1;
pow = pow(keep);
freq = (keep - 1)' * fs / n;
pow(1) = 0;
total = sum(pow, 'omitnan');
if total <= 1e-20
    total = 1e-20;
end
[~, idx] = max(pow);
spec.dominant_freq = freq(idx);
spec.spectral_centroid = sum(freq .* pow, 'omitnan') / total;
spec.low_band_energy = sum(pow(freq >= 0.5 & freq < 10), 'omitnan');
spec.mid_band_energy = sum(pow(freq >= 10 & freq < 100), 'omitnan');
spec.high_band_energy = sum(pow(freq >= 100), 'omitnan');
spec.high_band_ratio = spec.high_band_energy / total;
end

function cleanOutputDir(outputDir)
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
items = dir(outputDir);
for i = 1:numel(items)
    if items(i).isdir
        continue;
    end
    [~, ~, ext] = fileparts(items(i).name);
    if any(strcmpi(ext, {'.csv', '.md', '.png'}))
        delete(fullfile(outputDir, items(i).name));
    end
end
end

function makeFigures(det, feat, outputDir, cfg)
rep = selectRepresentativeRow(det);
saveChapter41RepresentativeTimeDomain(det(rep, :), cfg, fullfile(outputDir, 'chapter4_1_representative_multisource_time_domain.png'));
saveChapter41TimeResponse(det, cfg, fullfile(outputDir, 'chapter4_1_multisource_time_response_by_speed.png'));
saveChapter41SchemeEAnalysis(det, cfg, outputDir);
saveChapter42SvmdTimeDomain(det(rep, :), cfg, fullfile(outputDir, 'chapter4_2_svmd_time_domain_decomposition.png'));
saveChapter42SvmdFrequencySpectrum(det(rep, :), cfg, fullfile(outputDir, 'chapter4_2_svmd_frequency_spectrum.png'));
saveChapter42SteadySvmdTimeDomain(det(rep, :), cfg, fullfile(outputDir, 'chapter4_2_svmd_steady_time_domain_decomposition.png'));
saveChapter42SteadySvmdFrequencySpectrum(det(rep, :), cfg, fullfile(outputDir, 'chapter4_2_svmd_steady_frequency_spectrum.png'));
saveChapter42VibrationDifference(feat, fullfile(outputDir, 'chapter4_2_vibration_feature_point_difference.png'));
saveChapter42ThreePositionWaterfall(feat, fullfile(outputDir, 'chapter4_2_three_position_vibration_waterfall.png'));
saveChapter43ConditionInfluence(det, feat, fullfile(outputDir, 'chapter4_3_operating_condition_influence.png'));
saveChapter43ThreePositionVibration(feat, fullfile(outputDir, 'chapter4_3_three_position_vibration_condition.png'));
saveChapter43ThreePositionSpeedOpeningWaterfall(feat, fullfile(outputDir, 'chapter4_3_three_position_speed_opening_waterfall.png'));
saveChapter43PressureFlowThreePositionRelation(det, feat, fullfile(outputDir, 'chapter4_3_pressure_flow_three_position_relation.png'));
saveChapter43CorrelationMatrix(det, feat, fullfile(outputDir, 'chapter4_3_correlation_matrix.png'));
end

function exportChapter32FeatureTables(det, feat, outputDir, cfg)
%EXPORTCHAPTER32FEATURETABLES Export quantitative data supporting Section 3.2.
% Table 1: SVMD modal features for the same representative condition used
%          by the Chapter 4.2 SVMD figures.
% Table 2: Three-position non-stationary vibration statistics.
%
% This function only summarizes results already produced by the existing
% processing pipeline. It does not change AM-MEFD/SVMD detection results or
% the data used by the existing figures.

fprintf('\n============================================================\n');
fprintf('Section 3.2 quantitative feature tables\n');
fprintf('============================================================\n');

%% Table 1: representative-condition SVMD modal features
rep = selectRepresentativeRow(det);
row = det(rep, :);
raw = readRawXlsx(char(row.file_path));
fs = estimateFs(raw.time);
cfgLite = cfg;
cfgLite.useSVMD = false;
df = addCompositeSignals(raw, cfgLite, fs);
bt = row.burst_time;

% Keep this extraction window identical to the current Fig. 5 plotting
% functions so the tabulated modal parameters correspond to the plotted IMFs.
mask = df.time >= bt - 1.0 & df.time <= bt + 1.0;
x = sqrt(df.vibration_1_smooth(mask).^2 + df.vibration_2_smooth(mask).^2);
t = df.time(mask) - min(df.time(mask));
[imf, ~, fsWork] = computeSvmdImfsForPlot(x, t, fs, cfg);
if isempty(imf)
    warning('Section 3.2 SVMD feature table was not generated because SVMD decomposition failed.');
else
    nImf = size(imf, 2);
    modeName = strings(nImf, 1);
    centerFreq = nan(nImf, 1);
    peakFreq = nan(nImf, 1);
    modeRms = nan(nImf, 1);
    modeEnergy = nan(nImf, 1);

    for i = 1:nImf
        xi = imf(:, i);
        xi = xi(isfinite(xi));
        modeName(i) = "IMF" + string(i);
        if isempty(xi)
            continue;
        end
        modeRms(i) = sqrt(mean(xi.^2, 'omitnan'));
        modeEnergy(i) = sum(xi.^2, 'omitnan');

        [freq, amp] = singleSidedSpectrum(xi, fsWork);
        valid = isfinite(freq) & isfinite(amp);
        freq = freq(valid);
        amp = amp(valid);
        if ~isempty(freq)
            powerSpec = amp.^2;
            den = sum(powerSpec, 'omitnan');
            if isfinite(den) && den > 1e-12
                centerFreq(i) = sum(freq .* powerSpec, 'omitnan') / den;
            end
            [~, ip] = max(amp);
            if ~isempty(ip)
                peakFreq(i) = freq(ip);
            end
        end
    end

    totalEnergy = sum(modeEnergy, 'omitnan');
    if isfinite(totalEnergy) && totalEnergy > 1e-12
        energyRatioPct = 100 .* modeEnergy ./ totalEnergy;
    else
        energyRatioPct = zeros(nImf, 1);
    end

    svmdTable = table(modeName, centerFreq, peakFreq, modeRms, modeEnergy, energyRatioPct, ...
        'VariableNames', {'IMF','CenterFreq_Hz','PeakFreq_Hz','RMS','Energy','EnergyRatio_pct'});
    svmdPath = fullfile(outputDir, 'chapter3_2_svmd_modal_features.csv');
    writetable(svmdTable, svmdPath, 'Encoding', 'UTF-8');

    fprintf('\n[Table 3.2-1] Representative-condition SVMD modal features\n');
    fprintf('Condition: Speed = %g Hz, Opening = %g%%, Point = %s\n', ...
        row.speed, row.opening, char(string(row.point)));
    fprintf('Reference burst time: %.6f s\n', row.burst_time);
    fprintf('The extraction window is identical to the current Fig. 5 code: tb-1.0 s to tb+1.0 s.\n');
    disp(svmdTable);
    fprintf('CSV saved: %s\n', svmdPath);
end

%% Table 2: three-position non-stationary vibration statistics
posFeat = buildThreePositionFeatureTable(feat);
positions = {'固定测点','近爆管点测点','远爆管点测点'};
posShort = {'FP','NP','RP'};

nPos = numel(positions);
positionName = strings(nPos,1);
meanRms = nan(nPos,1);
minRms = nan(nPos,1);
maxRms = nan(nPos,1);
maxSpeed = nan(nPos,1);
maxOpening = nan(nPos,1);
meanPtp = nan(nPos,1);
meanStd = nan(nPos,1);
meanHfr = nan(nPos,1);

for p = 1:nPos
    sub = posFeat(posFeat.position == string(positions{p}), :);
    positionName(p) = string(posShort{p});
    if isempty(sub)
        continue;
    end

    % First average repeated records within each Speed-Opening condition.
    cond = unique(sub(:, {'speed','opening'}), 'rows');
    cond = sortrows(cond, {'speed','opening'});
    condRms = nan(height(cond),1);
    condPtp = nan(height(cond),1);
    condStd = nan(height(cond),1);
    condHfr = nan(height(cond),1);
    for c = 1:height(cond)
        cmask = sub.speed == cond.speed(c) & sub.opening == cond.opening(c);
        condRms(c) = mean(sub.rms(cmask), 'omitnan');
        condPtp(c) = mean(sub.ptp(cmask), 'omitnan');
        condStd(c) = mean(sub.std(cmask), 'omitnan');
        condHfr(c) = mean(sub.high_band_ratio(cmask), 'omitnan');
    end

    meanRms(p) = mean(condRms, 'omitnan');
    minRms(p) = min(condRms, [], 'omitnan');
    maxRms(p) = max(condRms, [], 'omitnan');
    meanPtp(p) = mean(condPtp, 'omitnan');
    meanStd(p) = mean(condStd, 'omitnan');
    meanHfr(p) = mean(condHfr, 'omitnan');

    finiteIdx = find(isfinite(condRms));
    if ~isempty(finiteIdx)
        [~, localIdx] = max(condRms(finiteIdx));
        maxIdx = finiteIdx(localIdx);
        maxSpeed(p) = cond.speed(maxIdx);
        maxOpening(p) = cond.opening(maxIdx);
    end
end

positionTable = table(positionName, meanRms, minRms, maxRms, maxSpeed, maxOpening, ...
    meanPtp, meanStd, meanHfr, ...
    'VariableNames', {'Position','Mean_RMS','Min_RMS','Max_RMS','MaxSpeed_Hz', ...
    'MaxOpening_pct','Mean_PTP','Mean_STD','Mean_HFR'});
posPath = fullfile(outputDir, 'chapter3_2_three_position_features.csv');
writetable(positionTable, posPath, 'Encoding', 'UTF-8');

fprintf('\n[Table 3.2-2] Three-position non-stationary vibration statistics\n');
fprintf('FP = fixed point, NP = near-burst point, RP = remote-burst point.\n');
fprintf('Mean/Min/Max RMS are calculated after averaging repeated records within each Speed-Opening condition.\n');
fprintf('PTP = peak-to-peak; STD = standard deviation; HFR = high-frequency energy ratio.\n');
disp(positionTable);
fprintf('CSV saved: %s\n', posPath);
fprintf('============================================================\n\n');
end


function exportChapter34FeatureTables(det, feat, outputDir)
%EXPORTCHAPTER34FEATURETABLES Export quantitative data supporting Section 3.4.
% Table 1: key Pearson correlation coefficients for Figure 10.
% Table 2: extreme-condition statistics of min-max normalized multi-source
%          features for Figure 11.
%
% The tables summarize variables already used by the existing 4.3 figures.
% They do not change detection, feature extraction, or plotting data.

fprintf('\n============================================================\n');
fprintf('Section 3.4 quantitative feature tables\n');
fprintf('============================================================\n');

condTbl = buildChapter34ConditionTable(det, feat);

%% Table 1: key Pearson correlation coefficients
pairs = {
    'Speed-PD',       'Speed',   'PD';
    'Speed-FI',       'Speed',   'FI';
    'Speed-F-RMS',    'Speed',   'F_RMS';
    'Speed-N-RMS',    'Speed',   'N_RMS';
    'Speed-R-RMS',    'Speed',   'R_RMS';
    'Opening-PD',     'Opening', 'PD';
    'Opening-FI',     'Opening', 'FI';
    'Opening-F-RMS',  'Opening', 'F_RMS';
    'Opening-N-RMS',  'Opening', 'N_RMS';
    'Opening-R-RMS',  'Opening', 'R_RMS';
    'BT-Speed',       'BT',      'Speed';
    'BT-FI',          'BT',      'FI';
    'BT-N-RMS',       'BT',      'N_RMS';
    'F-RMS-N-RMS',    'F_RMS',   'N_RMS';
    'F-RMS-R-RMS',    'F_RMS',   'R_RMS';
    'N-RMS-R-RMS',    'N_RMS',   'R_RMS'};
relation = string(pairs(:,1));
xVariable = string(pairs(:,2));
yVariable = string(pairs(:,3));
rValue = nan(size(relation));
for i = 1:numel(relation)
    rValue(i) = pearsonPair(condTbl.(char(xVariable(i))), condTbl.(char(yVariable(i))));
end
corrTable = table(relation, xVariable, yVariable, rValue, ...
    'VariableNames', {'Relation','XVariable','YVariable','Pearson_r'});
corrPath = fullfile(outputDir, 'chapter3_4_key_pearson_correlations.csv');
writetable(corrTable, corrPath, 'Encoding', 'UTF-8');

fprintf('\n[Table 3.4-1] Key Pearson correlation coefficients for Figure 10\n');
fprintf('Variables are based on 20 Speed-Opening conditions when available.\n');
disp(corrTable);
fprintf('CSV saved: %s\n', corrPath);

%% Table 2: extrema of normalized multi-source response indicators
metricNames = {'PD','FI','F-RMS','N-RMS','R-RMS'};
metricVars = {'PD','FI','F_RMS','N_RMS','R_RMS'};
rawMat = [condTbl.PD condTbl.FI condTbl.F_RMS condTbl.N_RMS condTbl.R_RMS];
normMat = normalizeMatrix(rawMat);
metric = strings(numel(metricVars),1);
maxNorm = nan(numel(metricVars),1); maxSpeed = nan(numel(metricVars),1); maxOpening = nan(numel(metricVars),1); maxRawValue = nan(numel(metricVars),1);
minNorm = nan(numel(metricVars),1); minSpeed = nan(numel(metricVars),1); minOpening = nan(numel(metricVars),1); minRawValue = nan(numel(metricVars),1);
meanNorm30Hz = nan(numel(metricVars),1); meanNorm50Hz = nan(numel(metricVars),1);
for i = 1:numel(metricVars)
    metric(i) = metricNames{i};
    y = normMat(:,i);
    raw = rawMat(:,i);
    valid = isfinite(y);
    if any(valid)
        validIdx = find(valid);
        [maxNorm(i), localMax] = max(y(validIdx));
        maxIdx = validIdx(localMax);
        [minNorm(i), localMin] = min(y(validIdx));
        minIdx = validIdx(localMin);
        maxSpeed(i) = condTbl.Speed(maxIdx);
        maxOpening(i) = condTbl.Opening(maxIdx);
        maxRawValue(i) = raw(maxIdx);
        minSpeed(i) = condTbl.Speed(minIdx);
        minOpening(i) = condTbl.Opening(minIdx);
        minRawValue(i) = raw(minIdx);
    end
    meanNorm30Hz(i) = mean(y(condTbl.Speed == 30), 'omitnan');
    meanNorm50Hz(i) = mean(y(condTbl.Speed == 50), 'omitnan');
end
extremeTable = table(metric, maxNorm, maxSpeed, maxOpening, maxRawValue, ...
    minNorm, minSpeed, minOpening, minRawValue, meanNorm30Hz, meanNorm50Hz, ...
    'VariableNames', {'Metric','MaxNorm','MaxSpeed_Hz','MaxOpening_pct','MaxRawValue', ...
    'MinNorm','MinSpeed_Hz','MinOpening_pct','MinRawValue','MeanNorm_30Hz','MeanNorm_50Hz'});
extremePath = fullfile(outputDir, 'chapter3_4_normalized_extreme_conditions.csv');
writetable(extremeTable, extremePath, 'Encoding', 'UTF-8');

fprintf('\n[Table 3.4-2] Extreme conditions of normalized multi-source indicators for Figure 11\n');
fprintf('PD, FI and three-position RMS are min-max normalized within each indicator.\n');
disp(extremeTable);
fprintf('CSV saved: %s\n', extremePath);
fprintf('============================================================\n\n');
end

function condTbl = buildChapter34ConditionTable(det, feat)
posFeat = buildThreePositionFeatureTable(feat);
positions = {'固定测点','近爆管点测点','远爆管点测点'};
cond = unique(det(:,{'speed','opening'}), 'rows');
cond = sortrows(cond, {'speed','opening'});
Speed = cond.speed;
Opening = cond.opening;
BT = nan(height(cond),1);
PD = nan(height(cond),1);
FI = nan(height(cond),1);
F_RMS = nan(height(cond),1);
N_RMS = nan(height(cond),1);
R_RMS = nan(height(cond),1);
for c = 1:height(cond)
    dMask = det.speed == cond.speed(c) & det.opening == cond.opening(c);
    BT(c) = mean(det.burst_time(dMask), 'omitnan');
    PD(c) = mean(det.final_pressure_drop_pct(dMask), 'omitnan');
    FI(c) = mean(det.final_flow_increase_pct(dMask), 'omitnan');
    for p = 1:3
        vMask = posFeat.speed == cond.speed(c) & posFeat.opening == cond.opening(c) & posFeat.position == string(positions{p});
        val = mean(posFeat.rms(vMask), 'omitnan');
        if p == 1
            F_RMS(c) = val;
        elseif p == 2
            N_RMS(c) = val;
        else
            R_RMS(c) = val;
        end
    end
end
condTbl = table(Speed, Opening, BT, PD, FI, F_RMS, N_RMS, R_RMS);
end

function r = pearsonPair(x, y)
x = x(:);
y = y(:);
valid = isfinite(x) & isfinite(y);
if nnz(valid) < 3 || std(x(valid),0,'omitnan') <= 1e-12 || std(y(valid),0,'omitnan') <= 1e-12
    r = NaN;
else
    cc = corrcoef(x(valid), y(valid));
    r = cc(1,2);
end
end

function idx = selectRepresentativeRow(det)
pointScore = zeros(height(det), 1);
points = unique(det.point, 'stable');
if ~isempty(points)
    pointScore(det.point ~= points(1)) = 0.2;
end
score = abs(det.speed - 40) ./ 10 + abs(det.opening - 80) ./ 40 + pointScore;
[~, idx] = min(score);
end

function saveChapter41RepresentativeTimeDomain(row, cfg, outPath)
raw = readRawXlsx(char(row.file_path)); fs = estimateFs(raw.time);
cfgLite = cfg; cfgLite.useSVMD = false; df = addCompositeSignals(raw, cfgLite, fs);
displayBt = estimatePressureDropOnsetTime(df, row.burst_time, cfg);
mask = df.time >= displayBt - 3.0 & df.time <= displayBt + 5.0;
t = df.time(mask) - displayBt;
series = {df.pressure_mean_smooth(mask), df.flow_smooth(mask), df.vibration_1_smooth(mask), df.vibration_2_smooth(mask)};
labels = {'压力/MPa','流量/(m^3/h)','FV/(mm/s)','NV/(mm/s)'}; if ~isNearExperiment(row.point), labels{4}='RV/(mm/s)'; end
colors=[0.35 0.22 0.20;0.18 0.45 0.42;0.74 0.57 0.18;0.28 0.54 0.75];
fig=paperFigure([17.2 13.2]); tl=tiledlayout(fig,4,1,'TileSpacing','compact','Padding','compact');
for i=1:4
 ax=nexttile(tl); hold(ax,'on'); plot(ax,t,series{i},'LineWidth',1.15,'Color',colors(i,:));
 xline(ax,0,'--r','BP','LineWidth',0.85,'FontSize',8,'LabelOrientation','horizontal','LabelVerticalAlignment','bottom');
 ylabel(ax,labels{i},'FontSize',9); xlim(ax,[-3 5]); xticks(ax,-3:1:5); paperAxes(ax,8);
 if i<4, ax.XTickLabel=[]; else, xlabel(ax,'时间/s','FontSize',9); end
end
title(tl,'多源时程响应','FontSize',10.5,'FontWeight','normal'); exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function saveChapter41TimeResponse(det, cfg, outPath)
relGrid=(-3.0:0.01:5.0)'; speeds=unique(det.speed); colors=lines(numel(speeds)); curve=struct();
for i=1:numel(speeds), curve(i).speed=speeds(i); curve(i).pressure=nan(numel(relGrid),0); curve(i).flow=nan(numel(relGrid),0); curve(i).vibration=nan(numel(relGrid),0); end
cfgLite=cfg; cfgLite.useSVMD=false;
for r=1:height(det)
 try
  raw=readRawXlsx(char(det.file_path(r))); fs=estimateFs(raw.time); df=addCompositeSignals(raw,cfgLite,fs);
  displayBt=estimatePressureDropOnsetTime(df,det.burst_time(r),cfg); relT=df.time-displayBt; baseMask=relT>=-2.0 & relT<=-0.3;
  if nnz(baseMask)<10, baseMask=df.time>=cfg.baselineStart & df.time<=cfg.baselineEnd; end
  preP=mean(df.pressure_mean_smooth(baseMask),'omitnan'); preF=mean(df.flow_smooth(baseMask),'omitnan'); vibAmp=sqrt(df.vibration_1_smooth.^2+df.vibration_2_smooth.^2); preV=mean(vibAmp(baseMask),'omitnan');
  pChange=(df.pressure_mean_smooth-preP)./max(abs(preP),1e-12)*100; fChange=(df.flow_smooth-preF)./max(abs(preF),1e-12)*100; vChange=(vibAmp-preV)./max(abs(preV),1e-12)*100;
  idx=find(speeds==det.speed(r),1); curve(idx).pressure(:,end+1)=interp1(relT,pChange,relGrid,'linear',NaN); curve(idx).flow(:,end+1)=interp1(relT,fChange,relGrid,'linear',NaN); curve(idx).vibration(:,end+1)=interp1(relT,vChange,relGrid,'linear',NaN);
 catch ME, fprintf('  time-response skip %s: %s\n',det.filename(r),ME.message); end
end
fig=paperFigure([17.2 12.5]); tl=tiledlayout(fig,3,1,'TileSpacing','compact','Padding','compact');
subTitles={'压力','流量','振动'}; ylabels={'\DeltaP (%)','\DeltaQ (%)','\DeltaV (%)'}; fields={'pressure','flow','vibration'}; lh=gobjects(numel(curve),1); axBottom=[];
for k=1:3
 ax=nexttile(tl); hold(ax,'on');
 for i=1:numel(curve), y=mean(curve(i).(fields{k}),2,'omitnan'); h=plot(ax,relGrid,y,'LineWidth',1.15,'Color',colors(i,:)); if k==3, lh(i)=h; end, end
 xline(ax,0,'--r','BP','LineWidth',0.85,'FontSize',8,'LabelOrientation','horizontal','LabelVerticalAlignment','bottom');
 title(ax,subTitles{k},'FontSize',9.2,'FontWeight','normal'); ylabel(ax,ylabels{k},'FontSize',9); xlim(ax,[-3 5]); xticks(ax,-3:1:5); paperAxes(ax,8);
 if k<3, ax.XTickLabel=[]; else, xlabel(ax,'时间/s','FontSize',9); axBottom=ax; end
end
% MATLAB releases differ in whether legend accepts a TiledChartLayout handle.
% Attach the shared legend to the bottom axes for broad compatibility.
legend(axBottom,lh,strcat(string(speeds),' Hz'),'Location','southoutside','Orientation','horizontal','NumColumns',numel(speeds),'FontSize',7.5,'Box','off');
title(tl,'多源响应','FontSize',10.5,'FontWeight','normal'); exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function saveChapter41Typical11DFeatureCurves(det, cfg, outPath)
% Plot the 11 measured channels for the typical 40 Hz / 80% condition.
[typicalRow, referencePoint] = selectTypical11DRow(det);
[fields, labels, units] = typical11DFields();
[tRel, values] = load11DCurve(typicalRow, cfg, fields);

fig = paperFigure([17.2 16.8]);
tl = tiledlayout(fig, 3, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
for j = 1:numel(fields)
    ax = nexttile(tl);
    [tPlot, yPlot] = downsampleCurve(tRel, values(:, j), 2500);
    plot(ax, tPlot, yPlot, 'Color', [0.00 0.32 0.58], 'LineWidth', 0.85);
    xline(ax, 0, '--r', 'LineWidth', 0.75);
    title(ax, labels{j}, 'FontSize', 8.8, 'FontWeight', 'normal');
    ylabel(ax, units{j}, 'FontSize', 7.8);
    xlim(ax, [-3 5]);
    xticks(ax, -3:1:5);
    paperAxes(ax, 7.2);
    if j <= 8
        ax.XTickLabel = [];
    else
        xlabel(ax, '相对时间/s', 'FontSize', 7.8);
    end
end
ax = nexttile(tl);
axis(ax, 'off');
title(tl, '典型工况11维特征曲线', 'FontSize', 10.5, 'FontWeight', 'normal');
exportgraphics(fig, outPath, 'Resolution', 600);
close(fig);
end

function saveChapter41Typical11DComparison(det, cfg, outPath)
% Compare every other condition with the typical curve at the same experiment point.
[typicalRow, referencePoint] = selectTypical11DRow(det);
[fields, labels, units] = typical11DFields();
mask = string(det.point) == string(referencePoint);
rows = det(mask, :);
rows = sortrows(rows, {'speed', 'opening', 'filename'});

fig = paperFigure([17.2 16.8]);
tl = tiledlayout(fig, 3, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
otherHandle = gobjects(1, 1);
typicalHandle = gobjects(1, 1);
for j = 1:numel(fields)
    ax = nexttile(tl);
    hold(ax, 'on');
    for r = 1:height(rows)
        [tRel, values] = load11DCurve(rows(r, :), cfg, fields);
        [tPlot, yPlot] = downsampleCurve(tRel, values(:, j), 1400);
        isTypical = rows.speed(r) == 40 && rows.opening(r) == 80;
        if isTypical
            h = plot(ax, tPlot, yPlot, 'Color', [0.80 0.05 0.05], 'LineWidth', 1.35);
            if ~isgraphics(typicalHandle), typicalHandle = h; end
        else
            h = plot(ax, tPlot, yPlot, 'Color', [0.72 0.72 0.72], 'LineWidth', 0.42);
            if ~isgraphics(otherHandle), otherHandle = h; end
        end
    end
    xline(ax, 0, '--k', 'LineWidth', 0.65);
    title(ax, labels{j}, 'FontSize', 8.8, 'FontWeight', 'normal');
    ylabel(ax, units{j}, 'FontSize', 7.8);
    xlim(ax, [-3 5]);
    xticks(ax, -3:1:5);
    paperAxes(ax, 7.2);
    if j <= 8
        ax.XTickLabel = [];
    else
        xlabel(ax, '相对时间/s', 'FontSize', 7.8);
    end
end
ax = nexttile(tl);
axis(ax, 'off');
if isgraphics(otherHandle) && isgraphics(typicalHandle)
    legend(ax, [otherHandle typicalHandle], {'其他工况', '典型工况 40-80'}, ...
        'Location', 'northwest', 'FontSize', 8, 'Box', 'off');
end
title(tl, '其他工况与典型11维特征曲线对比', 'FontSize', 10.5, 'FontWeight', 'normal');
exportgraphics(fig, outPath, 'Resolution', 600);
close(fig);
end

function [row, referencePoint] = selectTypical11DRow(det)
target = det.speed == 40 & det.opening == 80;
if ~any(target)
    error('Typical condition 40 Hz / 80%% was not found.');
end
points = string(det.point);
preferred = target & (contains(points, '振动点1') | contains(lower(points), 'point1'));
idx = find(preferred, 1, 'first');
if isempty(idx)
    idx = find(target, 1, 'first');
end
row = det(idx, :);
referencePoint = string(row.point(1));
end

function [fields, labels, units] = typical11DFields()
fields = {'pressure_1','pressure_2','pressure_3','pressure_4','pressure_5', ...
    'pressure_6','pressure_7','pressure_8','flow','vibration_1','vibration_2'};
labels = {'压力1','压力2','压力3','压力4','压力5','压力6','压力7','压力8','流量','振动1','振动2'};
units = {'MPa','MPa','MPa','MPa','MPa','MPa','MPa','MPa','m^3/h','mm/s','mm/s'};
end

function [tRel, values] = load11DCurve(row, cfg, fields)
raw = readRawXlsx(char(row.file_path));
bt = row.burst_time(1);
mask = raw.time >= bt - 3.0 & raw.time <= bt + 5.0;
if nnz(mask) < 20
    error('Not enough samples in the typical-comparison window for %s.', char(row.filename));
end
tRel = raw.time(mask) - bt;
values = raw{mask, fields};
end

function [tOut, yOut] = downsampleCurve(tIn, yIn, maxPoints)
tIn = tIn(:);
yIn = yIn(:);
valid = isfinite(tIn) & isfinite(yIn);
tIn = tIn(valid);
yIn = yIn(valid);
if numel(tIn) <= maxPoints
    tOut = tIn;
    yOut = yIn;
else
    idx = unique(round(linspace(1, numel(tIn), maxPoints))).';
    tOut = tIn(idx);
    yOut = yIn(idx);
end
end

function saveChapter41SchemeEAnalysis(det, cfg, outputDir)
% Build the complete Scheme F chain from the typical condition to all conditions.
[tTypical, typicalCube, channelLabels, modalityLabels, sourcePolicy] = ...
    buildPhysicalFeatureCubeForCondition(det, cfg, cfg.typicalSpeed, cfg.typicalOpening);
[featureNames, featureLabels] = windowFeatureDefinitions();

response = summarizeTypicalFeatureResponse(tTypical, typicalCube);
responseTable = array2table(response, 'VariableNames', featureNames);
responseTable = addvars(responseTable, string(channelLabels(:)), string(modalityLabels(:)), ...
    string(sourcePolicy(:)), 'Before', 1, ...
    'NewVariableNames', {'Channel','Modality','SourcePolicy'});
writetable(responseTable, fullfile(outputDir, ...
    'schemeF_typical_12channel_feature_response.csv'), 'Encoding', 'UTF-8');

zCube = standardizeWindowFeatureCube(tTypical, typicalCube);
postMask = tTypical >= 0 & tTypical <= 3.0;
if nnz(postMask) < 4
    error('Scheme F typical post-event window contains fewer than four feature windows.');
end

groupKeys = {'combined','pressure','flow','vibration'};
groupTitles = {'12路综合','压力','流量','振动'};
groupIndices = {1:12, 1:8, 9, 10:12};
corrMatrices = cell(size(groupKeys));
pMatrices = cell(size(groupKeys));
nMatrices = cell(size(groupKeys));
for g = 1:numel(groupKeys)
    observations = reshape(zCube(postMask, groupIndices{g}, :), [], numel(featureNames));
    [corrMatrices{g}, pMatrices{g}, nMatrices{g}] = ...
        pairwiseFeatureCorrelation(observations);
    prefix = sprintf('schemeF_typical_%s_feature_correlation', groupKeys{g});
    writeFeatureSquareMatrix(corrMatrices{g}, featureNames, featureLabels, ...
        fullfile(outputDir, [prefix '_matrix.csv']));
    writeFeatureSquareMatrix(pMatrices{g}, featureNames, featureLabels, ...
        fullfile(outputDir, [prefix '_pvalues.csv']));
    writeFeatureSquareMatrix(nMatrices{g}, featureNames, featureLabels, ...
        fullfile(outputDir, [prefix '_sample_counts.csv']));
    heatmapTitle = sprintf('典型工况 %g Hz-%g%% %s特征相关性', ...
        cfg.typicalSpeed, cfg.typicalOpening, groupTitles{g});
    saveSchemeEFeatureCorrelationHeatmap(corrMatrices{g}, featureLabels, heatmapTitle, ...
        fullfile(outputDir, [prefix '_heatmap.png']));
end

pairTable = buildSchemeEFeaturePairTable(groupKeys(2:4), ...
    corrMatrices(2:4), pMatrices(2:4), nMatrices(2:4), ...
    featureNames, featureLabels, cfg);
writetable(pairTable, fullfile(outputDir, ...
    'schemeF_typical_feature_correlation_pairs.csv'), 'Encoding', 'UTF-8');
[selected, selectedTable] = selectSchemeEStrongFeatures(pairTable, ...
    featureNames, featureLabels, cfg);
writetable(selectedTable, fullfile(outputDir, ...
    'schemeF_selected_strong_features.csv'), 'Encoding', 'UTF-8');

allConditionTable = buildSchemeEAllConditionTable(det, cfg, selected, ...
    featureNames, featureLabels);
writetable(allConditionTable, fullfile(outputDir, ...
    'schemeF_all_conditions_selected_feature_responses.csv'), 'Encoding', 'UTF-8');
saveSchemeEMultiSeriesCurves(allConditionTable, 'pressure', selected.pressure, ...
    featureNames, featureLabels, cfg, ...
    fullfile(outputDir, 'schemeF_all_conditions_pressure_selected_feature_curves.png'));
saveSchemeEFlowCurves(allConditionTable, selected.flow, featureNames, featureLabels, cfg, ...
    fullfile(outputDir, 'schemeF_all_conditions_flow_selected_feature_curves.png'));
saveSchemeEMultiSeriesCurves(allConditionTable, 'vibration', selected.vibration, ...
    featureNames, featureLabels, cfg, ...
    fullfile(outputDir, 'schemeF_all_conditions_vibration_selected_feature_curves.png'));

settings = table( ...
    ["TypicalSpeed_Hz";"TypicalOpening_pct";"StrongCorrelationThreshold"; ...
     "StrongCorrelationMinSamples";"MaxSelectedFeaturesPerModality"; ...
     "BaselineWindow_s";"PostEventWindow_s";"CorrelationObservationUnit"; ...
     "PValueInterpretation";"AllConditionReference"], ...
    [string(cfg.typicalSpeed);string(cfg.typicalOpening); ...
     string(cfg.strongCorrelationThreshold);string(cfg.strongCorrelationMinSamples); ...
     string(cfg.maxSelectedFeaturesPerModality);"-2.5 to -0.5";"0 to 3"; ...
     "baseline-standardized channel-window observations"; ...
     "exploratory only because sliding windows overlap"; ...
     "robust-scale difference from 40 Hz-80%"], ...
    'VariableNames', {'Setting','Value'});
writetable(settings, fullfile(outputDir, 'schemeF_analysis_settings.csv'), 'Encoding', 'UTF-8');
end

function [t, cube, labels, modalities, policies] = ...
        buildPhysicalFeatureCubeForCondition(det, cfg, speed, opening)
rows = det(det.speed == speed & det.opening == opening, :);
if isempty(rows)
    error('Condition %g Hz / %g%% was not found.', speed, opening);
end
nearMask = false(height(rows), 1);
for i = 1:height(rows)
    nearMask(i) = isNearExperiment(rows.point(i));
end
nearIdx = find(nearMask, 1, 'first');
farIdx = find(~nearMask, 1, 'first');
if isempty(nearIdx) || isempty(farIdx)
    error('Condition %g Hz / %g%% requires both vibration-point experiments.', speed, opening);
end

fields = {'pressure_1','pressure_2','pressure_3','pressure_4','pressure_5', ...
    'pressure_6','pressure_7','pressure_8','flow','vibration_1','vibration_2'};
families = [repmat("pressure", 1, 8), "flow", "vibration", "vibration"];
[tNear, nearCube] = extractWindowFeatureSeriesByFamily(rows(nearIdx,:), cfg, fields, families);
[tFar, farCube] = extractWindowFeatureSeriesByFamily(rows(farIdx,:), cfg, fields, families);
farCube = alignFeatureCube(tFar, farCube, tNear);
t = tNear;

% Pressure, flow and the fixed vibration are repeated in the two experiments.
% Average their aligned feature trajectories; retain the near/far moving sensors.
sharedCube = mean(cat(4, nearCube(:,1:10,:), farCube(:,1:10,:)), 4, 'omitnan');
cube = cat(2, sharedCube, nearCube(:,11,:), farCube(:,11,:));
labels = {'压力1','压力2','压力3','压力4','压力5','压力6','压力7','压力8', ...
    '流量','固定点振动','近爆管点振动','远爆管点振动'};
modalities = [repmat({'pressure'},1,8), {'flow'}, repmat({'vibration'},1,3)];
policies = [repmat({'两次同工况实验的对应滑窗特征均值'},1,9), ...
    {'两次同工况实验固定传感器的对应滑窗特征均值'}, ...
    {'振动点1实验的移动传感器'}, {'振动点2实验的移动传感器'}];
end

function [tCenters, featureValues] = extractWindowFeatureSeriesByFamily(row, cfg, fields, families)
raw = readRawXlsx(char(row.file_path));
fs = estimateFs(raw.time);
bt = row.burst_time(1);
starts = (bt - 3.0):cfg.stepSec:(bt + 5.0 - cfg.windowSec);
featureValues = nan(numel(starts), numel(fields), 9);
tCenters = nan(numel(starts), 1);
keepWindow = false(numel(starts), 1);
spectralValues = raw{:, fields};
smoothN = max(3, round(cfg.smoothSec * fs));
if mod(smoothN, 2) == 0
    smoothN = smoothN + 1;
end
smoothChannels = families == "pressure" | families == "flow";
spectralValues(:, smoothChannels) = movmedian( ...
    spectralValues(:, smoothChannels), smoothN, 1, 'omitnan');
for i = 1:numel(starts)
    mask = raw.time >= starts(i) & raw.time < starts(i) + cfg.windowSec;
    if nnz(mask) < max(10, round(0.25 * cfg.windowSec * fs))
        continue;
    end
    centerTime = starts(i) + cfg.windowSec / 2;
    spectralMask = raw.time >= centerTime - cfg.frequencyWindowSec / 2 & ...
        raw.time < centerTime + cfg.frequencyWindowSec / 2;
    featureValues(i,:,:) = computeWindowFeatureMatrixByFamily( ...
        raw{mask, fields}, spectralValues(spectralMask,:), fs, families);
    tCenters(i) = centerTime - bt;
    keepWindow(i) = true;
end
tCenters = tCenters(keepWindow);
featureValues = featureValues(keepWindow,:,:);
end

function out = computeWindowFeatureMatrixByFamily(x, xSpectral, fs, families)
out = nan(1, size(x,2), 9);
for ch = 1:size(x,2)
    v = x(:,ch);
    v = v(isfinite(v));
    if numel(v) < 4
        continue;
    end
    mu = mean(v);
    centered = v - mu;
    sd = std(v, 0);
    out(1,ch,1) = mu;
    out(1,ch,2) = sqrt(mean(v.^2));
    out(1,ch,3) = max(v) - min(v);
    out(1,ch,4) = sd;
    if sd > 1e-12
        z = centered ./ sd;
        out(1,ch,5) = mean(z.^3);
        out(1,ch,6) = mean(z.^4);
    else
        out(1,ch,5:6) = 0;
    end

    vSpectral = xSpectral(:,ch);
    vSpectral = vSpectral(isfinite(vSpectral));
    n = numel(vSpectral);
    if n < 8 || fs <= 0
        continue;
    end
    win = 0.5 - 0.5 * cos(2*pi*(0:n-1)'/max(n-1,1));
    y = detrend(vSpectral, 'linear') .* win;
    power = abs(fft(y)).^2;
    keep = 1:floor(n/2)+1;
    power = power(keep);
    freq = (keep-1)' * fs / n;
    power(1) = 0;
    if families(ch) == "pressure"
        upperHz = 60;
    elseif families(ch) == "flow"
        upperHz = 30;
    else
        upperHz = 200;
    end
    upperHz = min(upperHz, 0.45*fs);
    bandMask = freq >= max(0.5, fs/n) & freq <= upperHz;
    power(~bandMask) = 0;
    total = sum(power);
    if total <= 1e-20
        continue;
    end
    [~, peakIndex] = max(power);
    out(1,ch,7) = freq(peakIndex);
    out(1,ch,8) = sum(freq .* power) / total;
    prob = power / total;
    active = prob > 0;
    bandBinCount = nnz(bandMask);
    if bandBinCount > 1
        out(1,ch,9) = -sum(prob(active).*log2(prob(active))) / log2(bandBinCount);
    else
        out(1,ch,9) = 0;
    end
end
end

function aligned = alignFeatureCube(tSource, source, tTarget)
if numel(tSource) == numel(tTarget) && max(abs(tSource(:)-tTarget(:)), [], 'omitnan') < 1e-8
    aligned = source;
    return;
end
aligned = nan(numel(tTarget), size(source,2), size(source,3));
for ch = 1:size(source,2)
    for f = 1:size(source,3)
        y = source(:,ch,f);
        valid = isfinite(tSource) & isfinite(y);
        if nnz(valid) >= 2
            aligned(:,ch,f) = interp1(tSource(valid), y(valid), tTarget, 'linear', NaN);
        end
    end
end
end

function zCube = standardizeWindowFeatureCube(t, cube)
baseMask = t >= -2.5 & t <= -0.5;
zCube = nan(size(cube));
for ch = 1:size(cube,2)
    for f = 1:size(cube,3)
        y = cube(:,ch,f);
        base = y(baseMask & isfinite(y));
        allFinite = y(isfinite(y));
        if numel(base) < 4 || numel(allFinite) < 4
            continue;
        end
        center = median(base, 'omitnan');
        robustScale = 1.4826 * median(abs(base-center), 'omitnan');
        overallScale = std(allFinite, 0, 'omitnan');
        numericalFloor = max(1e-9, eps(max(abs(center),1)));
        scale = max([robustScale, 0.05*overallScale, numericalFloor]);
        zCube(:,ch,f) = (y-center) ./ scale;
    end
end
end

function writeFeatureSquareMatrix(matrix, featureNames, featureLabels, outPath)
tbl = array2table(matrix, 'VariableNames', featureNames);
tbl = addvars(tbl, string(featureLabels(:)), 'Before', 1, ...
    'NewVariableNames', 'Feature');
writetable(tbl, outPath, 'Encoding', 'UTF-8');
end

function saveSchemeEFeatureCorrelationHeatmap(matrix, featureLabels, titleText, outPath)
fig = paperFigure([16.8 15.8]);
ax = axes(fig);
imagesc(ax, 1:numel(featureLabels), 1:numel(featureLabels), matrix);
set(ax, 'YDir', 'reverse');
hold(ax, 'on');
colormap(ax, blueWhiteRedMap(257));
clim(ax, [-1 1]);
for x = 0.5:1:(numel(featureLabels)+0.5)
    xline(ax, x, '-', 'Color', [0.72 0.72 0.72], 'LineWidth', 0.35, ...
        'HandleVisibility', 'off');
end
for y = 0.5:1:(numel(featureLabels)+0.5)
    yline(ax, y, '-', 'Color', [0.72 0.72 0.72], 'LineWidth', 0.35, ...
        'HandleVisibility', 'off');
end
for row = 1:numel(featureLabels)
    for col = 1:numel(featureLabels)
        value = matrix(row,col);
        if ~isfinite(value)
            continue;
        end
        textColor = [0.08 0.08 0.08];
        if abs(value) >= 0.55
            textColor = [1 1 1];
        end
        text(ax, col, row, sprintf('%.3f',value), ...
            'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'FontSize',7,'FontWeight','bold','Color',textColor);
    end
end
xticks(ax,1:numel(featureLabels)); xticklabels(ax,featureLabels); xtickangle(ax,30);
yticks(ax,1:numel(featureLabels)); yticklabels(ax,featureLabels);
xlim(ax,[0.5 numel(featureLabels)+0.5]); ylim(ax,[0.5 numel(featureLabels)+0.5]);
pbaspect(ax,[1 1 1]); xlabel(ax,'特征','FontSize',9); ylabel(ax,'特征','FontSize',9);
title(ax,titleText,'FontSize',10.5,'FontWeight','normal');
cb = colorbar(ax,'eastoutside'); cb.FontSize=7.5; cb.TickDirection='in';
cb.Ticks=-1:0.2:1; cb.Label.String='Pearson r'; cb.Label.FontSize=8.2;
set(ax,'FontSize',8.2,'TickDir','in','TickLength',[0.010 0.010], ...
    'LineWidth',0.75,'Box','on','Layer','top');
exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function pairTable = buildSchemeEFeaturePairTable(modalities, corrCells, pCells, nCells, ...
        featureNames, featureLabels, cfg)
Modality = strings(0,1); Feature1 = strings(0,1); Feature2 = strings(0,1);
Feature1Label = strings(0,1); Feature2Label = strings(0,1);
Feature1Index = zeros(0,1); Feature2Index = zeros(0,1);
PearsonR = zeros(0,1); PValue = zeros(0,1); N = zeros(0,1);
for m = 1:numel(modalities)
    for i = 1:numel(featureNames)-1
        for j = i+1:numel(featureNames)
            Modality(end+1,1) = string(modalities{m}); %#ok<AGROW>
            Feature1(end+1,1) = string(featureNames{i}); %#ok<AGROW>
            Feature2(end+1,1) = string(featureNames{j}); %#ok<AGROW>
            Feature1Label(end+1,1) = string(featureLabels{i}); %#ok<AGROW>
            Feature2Label(end+1,1) = string(featureLabels{j}); %#ok<AGROW>
            Feature1Index(end+1,1) = i; %#ok<AGROW>
            Feature2Index(end+1,1) = j; %#ok<AGROW>
            PearsonR(end+1,1) = corrCells{m}(i,j); %#ok<AGROW>
            PValue(end+1,1) = pCells{m}(i,j); %#ok<AGROW>
            N(end+1,1) = nCells{m}(i,j); %#ok<AGROW>
        end
    end
end
AbsR = abs(PearsonR);
IsStrong = isfinite(PearsonR) & AbsR >= cfg.strongCorrelationThreshold & ...
    N >= cfg.strongCorrelationMinSamples;
pairTable = table(Modality,Feature1,Feature2,Feature1Label,Feature2Label, ...
    Feature1Index,Feature2Index,PearsonR,PValue,N,AbsR,IsStrong);
pairTable = sortrows(pairTable, {'Modality','AbsR'}, {'ascend','descend'});
end

function [selected, selectedTable] = selectSchemeEStrongFeatures(pairTable, ...
        featureNames, featureLabels, cfg)
modalityNames = {'pressure','flow','vibration'};
selected = struct();
Modality = strings(0,1); Feature = strings(0,1); FeatureLabel = strings(0,1);
FeatureIndex = zeros(0,1); BestAbsR = zeros(0,1); SelectionBasis = strings(0,1);
for m = 1:numel(modalityNames)
    modality = modalityNames{m};
    sub = pairTable(pairTable.Modality == string(modality) & pairTable.IsStrong, :);
    basis = "threshold";
    if isempty(sub)
        sub = pairTable(pairTable.Modality == string(modality) & isfinite(pairTable.PearsonR), :);
        sub = sortrows(sub, 'AbsR', 'descend');
        sub = sub(1:min(1,height(sub)), :);
        basis = "fallback strongest pair below threshold";
    end
    chosen = zeros(0,1);
    for r = 1:height(sub)
        candidates = [sub.Feature1Index(r), sub.Feature2Index(r)];
        for c = candidates
            if ~ismember(c, chosen) && numel(chosen) < cfg.maxSelectedFeaturesPerModality
                chosen(end+1,1) = c; %#ok<AGROW>
            end
        end
        if numel(chosen) >= cfg.maxSelectedFeaturesPerModality
            break;
        end
    end
    selected.(modality) = chosen(:).';
    modalityPairs = pairTable(pairTable.Modality == string(modality), :);
    for idx = chosen(:).'
        involved = modalityPairs.Feature1Index == idx | modalityPairs.Feature2Index == idx;
        best = max(modalityPairs.AbsR(involved), [], 'omitnan');
        Modality(end+1,1) = string(modality); %#ok<AGROW>
        Feature(end+1,1) = string(featureNames{idx}); %#ok<AGROW>
        FeatureLabel(end+1,1) = string(featureLabels{idx}); %#ok<AGROW>
        FeatureIndex(end+1,1) = idx; %#ok<AGROW>
        BestAbsR(end+1,1) = best; %#ok<AGROW>
        SelectionBasis(end+1,1) = basis; %#ok<AGROW>
    end
end
selectedTable = table(Modality,Feature,FeatureLabel,FeatureIndex,BestAbsR,SelectionBasis);
end

function tbl = buildSchemeEAllConditionTable(det, cfg, selected, featureNames, featureLabels)
conditions = unique(det(:,{'speed','opening'}), 'rows');
conditions = sortrows(conditions, {'speed','opening'});
Speed = zeros(0,1); Opening = zeros(0,1); Modality = strings(0,1);
Series = strings(0,1); Feature = strings(0,1); FeatureLabel = strings(0,1);
RawResponse = zeros(0,1);
for c = 1:height(conditions)
    speed = conditions.speed(c); opening = conditions.opening(c);
    [t, cube, channelLabels] = buildPhysicalFeatureCubeForCondition(det,cfg,speed,opening);
    response = summarizeTypicalFeatureResponse(t,cube);
    groups = {'pressure','flow','vibration'};
    channelGroups = {1:8, 9, 10:12};
    for g = 1:numel(groups)
        featureIdx = selected.(groups{g});
        for f = featureIdx
            for ch = channelGroups{g}
                Speed(end+1,1) = speed; %#ok<AGROW>
                Opening(end+1,1) = opening; %#ok<AGROW>
                Modality(end+1,1) = string(groups{g}); %#ok<AGROW>
                Series(end+1,1) = string(channelLabels{ch}); %#ok<AGROW>
                Feature(end+1,1) = string(featureNames{f}); %#ok<AGROW>
                FeatureLabel(end+1,1) = string(featureLabels{f}); %#ok<AGROW>
                RawResponse(end+1,1) = response(ch,f); %#ok<AGROW>
            end
        end
    end
end
tbl = table(Speed,Opening,Modality,Series,Feature,FeatureLabel,RawResponse);
tbl.TypicalResponse = nan(height(tbl),1);
tbl.ReferenceScale = nan(height(tbl),1);
tbl.RelativeToTypical = nan(height(tbl),1);
keys = unique(tbl(:,{'Modality','Series','Feature'}), 'rows');
for k = 1:height(keys)
    mask = tbl.Modality == keys.Modality(k) & tbl.Series == keys.Series(k) & ...
        tbl.Feature == keys.Feature(k);
    refMask = mask & tbl.Speed == cfg.typicalSpeed & tbl.Opening == cfg.typicalOpening;
    if nnz(refMask) ~= 1
        error('Scheme F expected one typical reference for %s/%s/%s.', ...
            keys.Modality(k), keys.Series(k), keys.Feature(k));
    end
    ref = tbl.RawResponse(refMask);
    values = tbl.RawResponse(mask);
    med = median(values,'omitnan');
    robustScale = 1.4826*median(abs(values-med),'omitnan');
    valueRange = max(values,[],'omitnan') - min(values,[],'omitnan');
    scale = max([robustScale,0.05*valueRange,1e-9]);
    tbl.TypicalResponse(mask) = ref;
    tbl.ReferenceScale(mask) = scale;
    tbl.RelativeToTypical(mask) = (values-ref)./scale;
end
tbl = sortrows(tbl, {'Modality','Feature','Series','Speed','Opening'});
end

function saveSchemeEMultiSeriesCurves(tbl, modality, featureIdx, ...
        featureNames, featureLabels, cfg, outPath)
sub = tbl(tbl.Modality == string(modality), :);
if isempty(featureIdx) || isempty(sub)
    warning('No Scheme F %s features were available for curve plotting.', modality);
    return;
end
n = numel(featureIdx); nCols = min(2,n); nRows = ceil(n/nCols);
fig = paperFigure([17.2 max(9.0,6.0*nRows)]);
tl = tiledlayout(fig,nRows,nCols,'TileSpacing','compact','Padding','compact');
legendHandles = gobjects(0); legendLabels = strings(0,1);
for p = 1:n
    ax = nexttile(tl); hold(ax,'on');
    fName = string(featureNames{featureIdx(p)});
    fSub = sub(sub.Feature == fName,:);
    seriesNames = unique(fSub.Series,'stable');
    colors = lines(numel(seriesNames));
    for s = 1:numel(seriesNames)
        rows = fSub(fSub.Series == seriesNames(s),:);
        rows = sortrows(rows,{'Speed','Opening'});
        h = plot(ax,1:height(rows),rows.RelativeToTypical,'-o', ...
            'LineWidth',1.05,'MarkerSize',3.0,'Color',colors(s,:), ...
            'MarkerFaceColor','w');
        if p == 1
            legendHandles(end+1,1) = h; %#ok<AGROW>
            legendLabels(end+1,1) = seriesNames(s); %#ok<AGROW>
        end
    end
    yline(ax,0,'-','Color',[0.35 0.35 0.35],'LineWidth',0.65,'HandleVisibility','off');
    conditionRows = sortrows(unique(fSub(:,{'Speed','Opening'}),'rows'),{'Speed','Opening'});
    typicalIndex = find(conditionRows.Speed==cfg.typicalSpeed & ...
        conditionRows.Opening==cfg.typicalOpening,1);
    if ~isempty(typicalIndex)
        xline(ax,typicalIndex,'--','Color',[0.78 0.08 0.08],'LineWidth',0.9, ...
            'HandleVisibility','off');
    end
    labels = strcat(string(conditionRows.Speed),"-",string(conditionRows.Opening));
    xticks(ax,1:height(conditionRows)); xticklabels(ax,labels); xtickangle(ax,45);
    xlim(ax,[0.5 height(conditionRows)+0.5]);
    title(ax,featureLabels{featureIdx(p)},'FontSize',9.2,'FontWeight','normal');
    ylabel(ax,'相对40-80基准/稳健尺度','FontSize',8.2);
    xlabel(ax,'工况（转速-开度）','FontSize',8.2); paperAxes(ax,7.2);
end
if ~isempty(legendHandles)
    legend(legendHandles,legendLabels,'Location','southoutside', ...
        'Orientation','horizontal','NumColumns',min(4,numel(legendLabels)), ...
        'FontSize',7,'Box','off');
end
if modality == "pressure"
    title(tl,'全部工况压力强相关特征相对变化','FontSize',10.5,'FontWeight','normal');
else
    title(tl,'全部工况三测点振动强相关特征相对变化','FontSize',10.5,'FontWeight','normal');
end
exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function saveSchemeEFlowCurves(tbl, featureIdx, featureNames, featureLabels, cfg, outPath)
sub = tbl(tbl.Modality == "flow",:);
if isempty(featureIdx) || isempty(sub)
    warning('No Scheme F flow features were available for curve plotting.');
    return;
end
fig = paperFigure([17.2 10.5]); ax = axes(fig); hold(ax,'on');
colors = lines(numel(featureIdx)); handles = gobjects(numel(featureIdx),1);
for p = 1:numel(featureIdx)
    fName = string(featureNames{featureIdx(p)});
    rows = sub(sub.Feature == fName,:);
    rows = sortrows(rows,{'Speed','Opening'});
    handles(p) = plot(ax,1:height(rows),rows.RelativeToTypical,'-o', ...
        'LineWidth',1.2,'MarkerSize',3.5,'Color',colors(p,:), ...
        'MarkerFaceColor','w');
end
yline(ax,0,'-','Color',[0.35 0.35 0.35],'LineWidth',0.65,'HandleVisibility','off');
conditionRows = sortrows(unique(sub(:,{'Speed','Opening'}),'rows'),{'Speed','Opening'});
typicalIndex = find(conditionRows.Speed==cfg.typicalSpeed & ...
    conditionRows.Opening==cfg.typicalOpening,1);
if ~isempty(typicalIndex)
    xline(ax,typicalIndex,'--','Color',[0.78 0.08 0.08],'LineWidth',0.9, ...
        'HandleVisibility','off');
end
labels = strcat(string(conditionRows.Speed),"-",string(conditionRows.Opening));
xticks(ax,1:height(conditionRows)); xticklabels(ax,labels); xtickangle(ax,45);
xlim(ax,[0.5 height(conditionRows)+0.5]);
xlabel(ax,'工况（转速-开度）','FontSize',9);
ylabel(ax,'相对40-80基准/稳健尺度','FontSize',9);
title(ax,'全部工况流量强相关特征相对变化','FontSize',10.5,'FontWeight','normal');
legend(ax,handles,string(featureLabels(featureIdx)),'Location','southoutside', ...
    'Orientation','horizontal','FontSize',7.5,'Box','off');
paperAxes(ax,8); exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function saveChapter41WindowFeatureSummaries(det, cfg, outputDir)
% Correlate nine feature-response patterns across the 11 measured channels.
[fields, channelLabels, ~] = typical11DFields();
[featureNames, featureLabels] = windowFeatureDefinitions();
[typicalRow, ~] = selectTypical11DRow(det);
[timeGrid, featureValues] = extractWindowFeatureSeries(typicalRow, cfg, fields);
response = summarizeTypicalFeatureResponse(timeGrid, featureValues);
[featureCorrelation, featurePValue, pairCount] = pairwiseFeatureCorrelation(response);

saveFeatureCorrelationHeatmap(featureCorrelation, featureLabels, ...
    typicalRow.speed(1), typicalRow.opening(1), ...
    fullfile(outputDir, 'chapter4_1_feature_correlation_heatmap.png'));

responseTable = array2table(response, 'VariableNames', featureNames);
responseTable = addvars(responseTable, string(channelLabels(:)), ...
    'Before', 1, 'NewVariableNames', 'Channel');
writetable(responseTable, fullfile(outputDir, ...
    'chapter4_1_combined_feature_response.csv'), 'Encoding', 'UTF-8');

correlationTable = array2table(featureCorrelation, 'VariableNames', featureNames);
correlationTable = addvars(correlationTable, string(featureLabels(:)), ...
    'Before', 1, 'NewVariableNames', 'Feature');
writetable(correlationTable, fullfile(outputDir, ...
    'chapter4_1_feature_correlation_matrix.csv'), 'Encoding', 'UTF-8');

pValueTable = array2table(featurePValue, 'VariableNames', featureNames);
pValueTable = addvars(pValueTable, string(featureLabels(:)), ...
    'Before', 1, 'NewVariableNames', 'Feature');
writetable(pValueTable, fullfile(outputDir, ...
    'chapter4_1_feature_correlation_pvalues.csv'), 'Encoding', 'UTF-8');

pairCountTable = array2table(pairCount, 'VariableNames', featureNames);
pairCountTable = addvars(pairCountTable, string(featureLabels(:)), ...
    'Before', 1, 'NewVariableNames', 'Feature');
writetable(pairCountTable, fullfile(outputDir, ...
    'chapter4_1_feature_correlation_sample_counts.csv'), 'Encoding', 'UTF-8');
end

function response = summarizeTypicalFeatureResponse(timeGrid, featureValues)
baselineMask = timeGrid >= -2.5 & timeGrid <= -0.5;
responseMask = timeGrid >= 0 & timeGrid <= 3.0;
response = nan(size(featureValues, 2), size(featureValues, 3));
for ch = 1:size(featureValues, 2)
    for f = 1:size(featureValues, 3)
        y = featureValues(:,ch,f);
        base = y(baselineMask & isfinite(y));
        post = y(responseMask & isfinite(y));
        allFinite = y(isfinite(y));
        if numel(base) < 4 || numel(post) < 4 || numel(allFinite) < 4
            continue;
        end
        center = median(base, 'omitnan');
        robustScale = 1.4826 * median(abs(base - center), 'omitnan');
        overallScale = std(allFinite, 0, 'omitnan');
        numericalFloor = max(1e-9, eps(max(abs(center), 1)));
        scale = max([robustScale, 0.05 * overallScale, numericalFloor]);
        response(ch,f) = (median(post, 'omitnan') - center) ./ scale;
    end
end
end

function [correlationMatrix, pValueMatrix, pairCount] = pairwiseFeatureCorrelation(response)
% Each feature is represented by its standardized response across 11 channels.
nFeatures = size(response, 2);
correlationMatrix = nan(nFeatures);
pValueMatrix = nan(nFeatures);
pairCount = zeros(nFeatures);
for i = 1:nFeatures
    for j = i:nFeatures
        valid = isfinite(response(:,i)) & isfinite(response(:,j));
        n = nnz(valid);
        pairCount(i,j) = n;
        pairCount(j,i) = n;
        if n < 3
            continue;
        end
        xi = response(valid,i);
        xj = response(valid,j);
        if std(xi, 0, 'omitnan') <= 1e-12 || std(xj, 0, 'omitnan') <= 1e-12
            continue;
        end
        [cc, pp] = corrcoef(xi, xj);
        correlationMatrix(i,j) = cc(1,2);
        correlationMatrix(j,i) = cc(1,2);
        pValueMatrix(i,j) = pp(1,2);
        pValueMatrix(j,i) = pp(1,2);
    end
end
for i = 1:nFeatures
    if pairCount(i,i) >= 3
        correlationMatrix(i,i) = 1;
        pValueMatrix(i,i) = 0;
    end
end
end

function saveFeatureCorrelationHeatmap(correlationMatrix, featureLabels, speed, opening, outPath)
fig = paperFigure([16.8 15.8]);
ax = axes(fig);
imagesc(ax, 1:numel(featureLabels), 1:numel(featureLabels), correlationMatrix);
set(ax, 'YDir', 'reverse');
hold(ax, 'on');
colormap(ax, blueWhiteRedMap(257));
clim(ax, [-1 1]);

for x = 0.5:1:(numel(featureLabels) + 0.5)
    xline(ax, x, '-', 'Color', [0.72 0.72 0.72], 'LineWidth', 0.35, 'HandleVisibility', 'off');
end
for y = 0.5:1:(numel(featureLabels) + 0.5)
    yline(ax, y, '-', 'Color', [0.72 0.72 0.72], 'LineWidth', 0.35, 'HandleVisibility', 'off');
end
for row = 1:numel(featureLabels)
    for col = 1:numel(featureLabels)
        value = correlationMatrix(row,col);
        if ~isfinite(value)
            continue;
        end
        if abs(value) >= 0.55
            textColor = [1 1 1];
        else
            textColor = [0.08 0.08 0.08];
        end
        text(ax, col, row, sprintf('%.3f', value), 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'FontSize', 7.0, ...
            'FontWeight', 'bold', 'Color', textColor);
    end
end

xticks(ax, 1:numel(featureLabels));
xticklabels(ax, featureLabels);
xtickangle(ax, 30);
yticks(ax, 1:numel(featureLabels));
yticklabels(ax, featureLabels);
xlim(ax, [0.5 numel(featureLabels) + 0.5]);
ylim(ax, [0.5 numel(featureLabels) + 0.5]);
pbaspect(ax, [1 1 1]);
xlabel(ax, '特征', 'FontSize', 9);
ylabel(ax, '特征', 'FontSize', 9);
title(ax, sprintf('典型工况 %g Hz-%g%% 特征响应相关性', speed, opening), ...
    'FontSize', 10.5, 'FontWeight', 'normal');
cb = colorbar(ax, 'eastoutside');
cb.FontSize = 7.5;
cb.TickDirection = 'in';
cb.Ticks = -1:0.2:1;
cb.Label.String = 'Pearson r';
cb.Label.FontSize = 8.2;
set(ax, 'FontSize', 8.2, 'TickDir', 'in', 'TickLength', [0.010 0.010], ...
    'LineWidth', 0.75, 'Box', 'on', 'Layer', 'top');
exportgraphics(fig, outPath, 'Resolution', 600);
close(fig);
end

function map = blueWhiteRedMap(n)
anchors = [0.16 0.36 0.62; 0.96 0.96 0.96; 0.72 0.16 0.16];
x = [0 0.5 1];
xi = linspace(0, 1, n);
map = interp1(x, anchors, xi, 'linear');
end

function [names, labels] = windowFeatureDefinitions()
names = {'mean','rms','ptp','std','skewness','kurtosis', ...
    'dominant_frequency','spectral_centroid','spectral_entropy'};
labels = {'均值','RMS','峰峰值','标准差','偏度','峭度', ...
    '主频','频谱质心','频谱熵'};
end

function [tCenters, featureValues] = extractWindowFeatureSeries(row, cfg, fields)
raw = readRawXlsx(char(row.file_path));
fs = estimateFs(raw.time);
bt = row.burst_time(1);
starts = (bt - 3.0):cfg.stepSec:(bt + 5.0 - cfg.windowSec);
featureValues = nan(numel(starts), numel(fields), 9);
tCenters = nan(numel(starts), 1);
keep = false(numel(starts), 1);
spectralValues = raw{:, fields};
smoothN = max(3, round(cfg.smoothSec * fs));
if mod(smoothN, 2) == 0
    smoothN = smoothN + 1;
end
% Pressure and flow contain a strong near-Nyquist acquisition component.
% Smooth those channels before spectral estimation only; time-domain
% features below continue to use the original measurements.
spectralValues(:, 1:9) = movmedian(spectralValues(:, 1:9), smoothN, 1, 'omitnan');
for i = 1:numel(starts)
    mask = raw.time >= starts(i) & raw.time < starts(i) + cfg.windowSec;
    if nnz(mask) < max(10, round(0.25 * cfg.windowSec * fs))
        continue;
    end
    x = raw{mask, fields};
    centerTime = starts(i) + cfg.windowSec / 2;
    spectralMask = raw.time >= centerTime - cfg.frequencyWindowSec / 2 & ...
        raw.time < centerTime + cfg.frequencyWindowSec / 2;
    xSpectral = spectralValues(spectralMask, :);
    featureValues(i, :, :) = computeWindowFeatureMatrix(x, xSpectral, fs);
    tCenters(i) = starts(i) + cfg.windowSec / 2 - bt;
    keep(i) = true;
end
tCenters = tCenters(keep);
featureValues = featureValues(keep, :, :);
end

function out = computeWindowFeatureMatrix(x, xSpectral, fs)
out = nan(1, size(x, 2), 9);
for ch = 1:size(x, 2)
    v = x(:, ch);
    v = v(isfinite(v));
    if numel(v) < 4
        continue;
    end
    mu = mean(v);
    centered = v - mu;
    sd = std(v, 0);
    out(1, ch, 1) = mu;
    out(1, ch, 2) = sqrt(mean(v.^2));
    out(1, ch, 3) = max(v) - min(v);
    out(1, ch, 4) = sd;
    if sd > 1e-12
        z = centered ./ sd;
        out(1, ch, 5) = mean(z.^3);
        out(1, ch, 6) = mean(z.^4);
    else
        out(1, ch, 5:6) = 0;
    end

    vSpectral = xSpectral(:, ch);
    vSpectral = vSpectral(isfinite(vSpectral));
    n = numel(vSpectral);
    if n < 8 || fs <= 0
        continue;
    end
    if n == 1
        win = 1;
    else
        win = 0.5 - 0.5 * cos(2 * pi * (0:n-1)' / (n-1));
    end
    % Remove the local linear trend before spectral estimation so a pressure
    % ramp inside the short window is not mistaken for an oscillation.
    y = detrend(vSpectral, 'linear') .* win;
    power = abs(fft(y)).^2;
    keep = 1:floor(n / 2) + 1;
    power = power(keep);
    freq = (keep - 1)' * fs / n;
    power(1) = 0;
    % Keep only the physically useful band for each sensor family and stay
    % below the Nyquist edge, where the pressure channels contain acquisition
    % noise that previously forced peaks to about 295--300 Hz.
    if ch <= 8
        upperHz = 60;  % pressure: covers the 30--50 Hz operating range
    elseif ch == 9
        upperHz = 30;  % flow
    else
        upperHz = 200; % vibration
    end
    upperHz = min(upperHz, 0.45 * fs);
    bandMask = freq >= max(0.5, fs / n) & freq <= upperHz;
    power(~bandMask) = 0;
    total = sum(power);
    if total <= 1e-20
        continue;
    end
    [~, peakIndex] = max(power);
    out(1, ch, 7) = freq(peakIndex);
    out(1, ch, 8) = sum(freq .* power) / total;
    prob = power / total;
    active = prob > 0;
    bandBinCount = nnz(bandMask);
    if bandBinCount > 1
        out(1, ch, 9) = -sum(prob(active) .* log2(prob(active))) / log2(bandBinCount);
    else
        out(1, ch, 9) = 0;
    end
end
end

function displayBt = estimatePressureDropOnsetTime(df, burstTime, cfg)
% Use the AM-MEFD/SVMD result as an anchor, then move the displayed marker
% to the front edge of the continuous pressure-drop trend for clearer physics.
t = df.time(:);
p = df.pressure_mean_smooth(:);
displayBt = burstTime;
valid = isfinite(t) & isfinite(p);
if nnz(valid) < 20 || ~isfinite(burstTime)
    return;
end
t = t(valid);
p = p(valid);
baseMask = t >= max(cfg.baselineStart, burstTime - 2.5) & t <= max(cfg.baselineStart, burstTime - 0.45);
if nnz(baseMask) < 20
    baseMask = t >= cfg.baselineStart & t <= cfg.baselineEnd;
end
baseP = median(p(baseMask), 'omitnan');
if ~isfinite(baseP) || abs(baseP) < 1e-12
    return;
end
searchMask = t >= max(cfg.detectStart, burstTime - 1.6) & t <= min(cfg.detectEnd, burstTime + 0.25);
if nnz(searchMask) < 20
    return;
end
ts = t(searchMask);
ps = p(searchMask);
dropPct = (baseP - ps) ./ max(abs(baseP), 1e-12) * 100;
dropPct = movmedian(dropPct, 21, 'omitnan');
maxDrop = max(dropPct, [], 'omitnan');
if ~isfinite(maxDrop) || maxDrop <= 0
    return;
end
frontThreshold = max(0.25, 0.025 * maxDrop);
confirmThreshold = max(1.5, 0.10 * maxDrop);
confirmSamples = max(5, round(0.18 / max(median(diff(ts), 'omitnan'), 1e-3)));
idx = [];
for i = 1:(numel(ts) - confirmSamples)
    nowHit = dropPct(i) >= frontThreshold;
    laterHit = max(dropPct(i:min(numel(ts), i + confirmSamples)), [], 'omitnan') >= confirmThreshold;
    if nowHit && laterHit
        idx = i;
        break;
    end
end
if isempty(idx)
    idx = find(dropPct >= max(0.5, 0.06 * maxDrop), 1, 'first');
end
if isempty(idx)
    return;
end
dp = gradient(ps, ts);
back = idx;
while back > 1 && dp(back - 1) < 0
    back = back - 1;
end
displayBt = ts(back);
if displayBt > burstTime || displayBt < burstTime - 1.6
    displayBt = ts(idx);
end
end
function saveChapter42SvmdTimeDomain(row, cfg, outPath)
raw=readRawXlsx(char(row.file_path)); fs=estimateFs(raw.time); cfgLite=cfg; cfgLite.useSVMD=false; df=addCompositeSignals(raw,cfgLite,fs); bt=row.burst_time;
mask=df.time>=bt-1.0 & df.time<=bt+1.0; x=sqrt(df.vibration_1_smooth(mask).^2+df.vibration_2_smooth(mask).^2); t=df.time(mask)-min(df.time(mask));
[imf,tWork,~]=computeSvmdImfsForPlot(x,t,fs,cfg); if isempty(imf), error('SVMD decomposition failed for representative figure.'); end
nImf=size(imf,2); fig=paperFigure([17.2 13.2]); tl=tiledlayout(fig,nImf,1,'TileSpacing','compact','Padding','compact');
modeLabels=strcat("IMF",string(1:nImf)); modeLabels(end)=modeLabels(end)+"（低频趋势项）";
for i=1:nImf
 ax=nexttile(tl); plot(ax,tWork,imf(:,i),'LineWidth',1.1,'Color',imfColor(i)); ylabel(ax,modeLabels(i),'FontSize',9); xlim(ax,[min(tWork),max(tWork)]); paperAxes(ax,8); box(ax,'on');
 if i<nImf, ax.XTickLabel=[]; else, xlabel(ax,'时间/s','FontSize',9); end
end
title(tl,'SVMD时域模态','FontSize',10.5,'FontWeight','normal'); exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function saveChapter42SvmdFrequencySpectrum(row, cfg, outPath)
raw=readRawXlsx(char(row.file_path)); fs=estimateFs(raw.time); cfgLite=cfg; cfgLite.useSVMD=false; df=addCompositeSignals(raw,cfgLite,fs); bt=row.burst_time;
mask=df.time>=bt-1.0 & df.time<=bt+1.0; x=sqrt(df.vibration_1_smooth(mask).^2+df.vibration_2_smooth(mask).^2); t=df.time(mask)-min(df.time(mask));
[imf,~,fsWork]=computeSvmdImfsForPlot(x,t,fs,cfg); if isempty(imf), error('SVMD decomposition failed for representative figure.'); end
nImf=size(imf,2); fig=paperFigure([17.2 10.5]); ax3=axes(fig); hold(ax3,'on'); fMaxPlot=min(150,fsWork/2);
modeLabels=strcat("IMF",string(1:nImf)); modeLabels(end)=modeLabels(end)+"（低频趋势项）";
for i=1:nImf
 [freq,amp]=singleSidedSpectrum(imf(:,i),fsWork); show=freq<=fMaxPlot; freq=freq(show); amp=amp(show); am=max(amp,[],'omitnan'); if isfinite(am)&&am>0, amp=amp./am; end; y=i*ones(size(freq));
 if numel(freq)>1, patch(ax3,[freq;flipud(freq)],[y;flipud(y)],[amp;zeros(size(amp))],imfColor(i),'FaceAlpha',0.06,'EdgeColor','none','HandleVisibility','off'); end
 plot3(ax3,freq,y,amp,'LineWidth',1.15,'Color',imfColor(i));
end
xlabel(ax3,'频率/Hz','FontSize',9); ylabel(ax3,'模态','FontSize',9); zlabel(ax3,'归一化幅值','FontSize',9); yticks(ax3,1:nImf); yticklabels(ax3,modeLabels); xlim(ax3,[0 fMaxPlot]); zlim(ax3,[0 1.05]);
pbaspect(ax3,[2.6 1.0 0.55]); camproj(ax3,'orthographic'); view(ax3,[-48 22]); set(ax3,'FontSize',8,'TickDir','in','LineWidth',0.75,'Box','off','XGrid','off','YGrid','off','ZGrid','off');
title(ax3,'SVMD频谱','FontSize',10.5,'FontWeight','normal'); exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function saveChapter42SteadySvmdTimeDomain(row, cfg, outPath)
[x,t,fs]=steadySvmdInput(row,cfg);
[imf,tWork,~]=computeSvmdImfsForPlot(x,t,fs,cfg); if isempty(imf), error('Steady-state SVMD decomposition failed for representative figure.'); end
nImf=size(imf,2); fig=paperFigure([17.2 13.2]); tl=tiledlayout(fig,nImf,1,'TileSpacing','compact','Padding','compact');
modeLabels=strcat("IMF",string(1:nImf)); modeLabels(end)=modeLabels(end)+"（低频趋势项）";
for i=1:nImf
 ax=nexttile(tl); plot(ax,tWork,imf(:,i),'LineWidth',1.1,'Color',imfColor(i)); ylabel(ax,modeLabels(i),'FontSize',9); xlim(ax,[min(tWork),max(tWork)]); paperAxes(ax,8); box(ax,'on');
 if i<nImf, ax.XTickLabel=[]; else, xlabel(ax,'时间/s','FontSize',9); end
end
title(tl,'稳态SVMD时域模态','FontSize',10.5,'FontWeight','normal'); exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function saveChapter42SteadySvmdFrequencySpectrum(row, cfg, outPath)
[x,t,fs]=steadySvmdInput(row,cfg);
[imf,~,fsWork]=computeSvmdImfsForPlot(x,t,fs,cfg); if isempty(imf), error('Steady-state SVMD decomposition failed for representative figure.'); end
nImf=size(imf,2); fig=paperFigure([17.2 10.5]); ax3=axes(fig); hold(ax3,'on'); fMaxPlot=min(150,fsWork/2);
modeLabels=strcat("IMF",string(1:nImf)); modeLabels(end)=modeLabels(end)+"（低频趋势项）";
for i=1:nImf
 [freq,amp]=singleSidedSpectrum(imf(:,i),fsWork); show=freq<=fMaxPlot; freq=freq(show); amp=amp(show); am=max(amp,[],'omitnan'); if isfinite(am)&&am>0, amp=amp./am; end; y=i*ones(size(freq));
 if numel(freq)>1, patch(ax3,[freq;flipud(freq)],[y;flipud(y)],[amp;zeros(size(amp))],imfColor(i),'FaceAlpha',0.06,'EdgeColor','none','HandleVisibility','off'); end
 plot3(ax3,freq,y,amp,'LineWidth',1.15,'Color',imfColor(i));
end
xlabel(ax3,'频率/Hz','FontSize',9); ylabel(ax3,'模态','FontSize',9); zlabel(ax3,'归一化幅值','FontSize',9); yticks(ax3,1:nImf); yticklabels(ax3,modeLabels); xlim(ax3,[0 fMaxPlot]); zlim(ax3,[0 1.05]);
pbaspect(ax3,[2.6 1.0 0.55]); camproj(ax3,'orthographic'); view(ax3,[-48 22]); set(ax3,'FontSize',8,'TickDir','in','LineWidth',0.75,'Box','off','XGrid','off','YGrid','off','ZGrid','off');
title(ax3,'稳态SVMD频谱','FontSize',10.5,'FontWeight','normal'); exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function [x,t,fs]=steadySvmdInput(row,cfg)
raw=readRawXlsx(char(row.file_path)); fs=estimateFs(raw.time); cfgLite=cfg; cfgLite.useSVMD=false; df=addCompositeSignals(raw,cfgLite,fs);
steadyEnd=cfg.baselineEnd; steadyStart=max(cfg.baselineStart,steadyEnd-2.0); mask=df.time>=steadyStart & df.time<=steadyEnd;
if nnz(mask)<128, error('Steady-state SVMD window [%.3f, %.3f] s contains too few samples.',steadyStart,steadyEnd); end
x=sqrt(df.vibration_1_smooth(mask).^2+df.vibration_2_smooth(mask).^2); t=df.time(mask)-min(df.time(mask));
end

function forceInwardTicks(ax)
set(ax, 'TickDir', 'in', 'TickLength', [0.018 0.018]);
try
    ax.XRuler.TickDirection = 'in';
    ax.YRuler.TickDirection = 'in';
    ax.ZRuler.TickDirection = 'in';
catch
end
end

function [imf, tWork, fsWork] = computeSvmdImfsForPlot(x, t, fs, cfg)
imf = [];
x = x(:);
t = t(:);
valid = isfinite(x) & isfinite(t);
x = x(valid);
t = t(valid);
if numel(x) < 128 || exist('vmd', 'file') ~= 2
    return;
end
if numel(x) > cfg.svmdMaxSamples
    sampleIdx = unique(round(linspace(1, numel(x), cfg.svmdMaxSamples))).';
    xWork = x(sampleIdx);
    tWork = t(sampleIdx);
else
    xWork = x;
    tWork = t;
end
xWork = fillmissing(xWork, 'linear', 'EndValues', 'nearest');
s = std(xWork, 'omitnan');
if ~isfinite(s) || s <= 1e-12
    return;
end
xWork = (xWork - mean(xWork, 'omitnan')) ./ s;
try
    imf = svmdLocal(xWork, cfg);
    if size(imf, 1) ~= numel(xWork) && size(imf, 2) == numel(xWork)
        imf = imf.';
    end
    dt = median(diff(tWork), 'omitnan');
    if isfinite(dt) && dt > 0
        fsWork = 1 / dt;
    else
        fsWork = fs;
    end
catch
    imf = [];
    fsWork = fs;
end
end

function [freq, amp] = singleSidedSpectrum(x, fs)
x = x(:) - mean(x, 'omitnan');
n = numel(x);
y = abs(fft(x)) / max(n, 1);
keep = 1:floor(n/2)+1;
amp = y(keep);
freq = (keep - 1)' * fs / n;
if numel(amp) > 2
    amp(2:end-1) = 2 * amp(2:end-1);
end
end

function c = imfColor(i)
palette = [0.40 0.25 0.22; 0.18 0.48 0.45; 0.75 0.58 0.18; 0.50 0.35 0.62; 0.19 0.55 0.39; 0.20 0.48 0.72; 0.75 0.28 0.22; 0.30 0.30 0.30];
c = palette(mod(i-1, size(palette, 1)) + 1, :);
end

function saveChapter42VibrationDifference(feat, outPath)
posFeat=buildThreePositionFeatureTable(feat); positions={'固定测点','近爆管点测点','远爆管点测点'}; posShort={'FP','NP','RP'}; speeds=unique(posFeat.speed);
fig=paperFigure([17.2 12.5]); tl=tiledlayout(fig,2,1,'TileSpacing','compact','Padding','compact');
ax1=nexttile(tl); rmsData=meanPositionMatrix(posFeat,speeds,positions,'rms'); bar(ax1,rmsData,'grouped'); xticks(ax1,1:numel(speeds)); xticklabels(ax1,string(speeds)); ylabel(ax1,'RMS','FontSize',9); xlabel(ax1,'转速/Hz','FontSize',9); title(ax1,'RMS','FontSize',9.2,'FontWeight','normal'); paperAxes(ax1,8); legend(ax1,posShort,'Location','northwest','Orientation','horizontal','FontSize',7.5,'Box','off');
ax2=nexttile(tl); ptpData=meanPositionMatrix(posFeat,speeds,positions,'ptp'); stdData=meanPositionMatrix(posFeat,speeds,positions,'std'); highData=meanPositionMatrix(posFeat,speeds,positions,'high_band_ratio'); summaryData=[mean(rmsData,1,'omitnan');mean(ptpData,1,'omitnan');mean(stdData,1,'omitnan');mean(highData,1,'omitnan')]'; summaryNorm=normalizeMatrix(summaryData); bar(ax2,summaryNorm,'grouped'); xticks(ax2,1:3); xticklabels(ax2,posShort); ylabel(ax2,'归一化值','FontSize',9); xlabel(ax2,'测点','FontSize',9); title(ax2,'归一化特征','FontSize',9.2,'FontWeight','normal'); paperAxes(ax2,8); legend(ax2,{'RMS','PTP','STD','HFR'},'Location','northoutside','Orientation','horizontal','FontSize',7.5,'Box','off');
title(tl,'振动特征','FontSize',10.5,'FontWeight','normal'); exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function posFeat = buildThreePositionFeatureTable(feat)
rows = struct([]);
for r = 1:height(feat)
    rows = appendStruct(rows, positionFeatureRow(feat, r, '固定测点', 'vibration_1'));
    if isNearExperiment(feat.point(r))
        posName = '近爆管点测点';
    else
        posName = '远爆管点测点';
    end
    rows = appendStruct(rows, positionFeatureRow(feat, r, posName, 'vibration_2'));
end
posFeat = struct2table(rows);
end

function row = positionFeatureRow(feat, r, posName, prefix)
row.position = string(posName);
row.experiment = feat.point(r);
row.speed = feat.speed(r);
row.opening = feat.opening(r);
row.filename = feat.filename(r);
row.rms = feat.(sprintf('%s_rms', prefix))(r);
row.std = feat.(sprintf('%s_std', prefix))(r);
row.ptp = feat.(sprintf('%s_ptp', prefix))(r);
row.energy = feat.(sprintf('%s_energy', prefix))(r);
row.spectral_centroid = feat.(sprintf('%s_spectral_centroid', prefix))(r);
row.high_band_ratio = feat.(sprintf('%s_high_band_ratio', prefix))(r);
end

function tf = isNearExperiment(pointName)
s = string(pointName);
tf = contains(s, '1') || contains(s, '近');
end

function label = movingPointLabel(pointName)
if isNearExperiment(pointName)
    label = '近爆管点测点 (mm/s)';
else
    label = '远爆管点测点 (mm/s)';
end
end

function mat = meanPositionMatrix(posFeat, speeds, positions, valueName)
mat = nan(numel(speeds), numel(positions));
for i = 1:numel(speeds)
    for j = 1:numel(positions)
        mask = posFeat.speed == speeds(i) & posFeat.position == string(positions{j});
        mat(i, j) = mean(posFeat.(valueName)(mask), 'omitnan');
    end
end
end
function saveChapter42ThreePositionWaterfall(feat, outPath)
posFeat=buildThreePositionFeatureTable(feat); positions={'固定测点','近爆管点测点','远爆管点测点'}; posShort={'FP','NP','RP'}; cond=unique(posFeat(:,{'speed','opening'}),'rows'); cond=sortrows(cond,{'speed','opening'}); z=nan(3,height(cond));
for p=1:3, for c=1:height(cond), mask=posFeat.position==string(positions{p}) & posFeat.speed==cond.speed(c) & posFeat.opening==cond.opening(c); z(p,c)=mean(posFeat.rms(mask),'omitnan'); end, end
zNorm=normalizeMatrix(z); fig=paperFigure([17.2 10.5]); ax=axes(fig); hold(ax,'on'); cc=[0.00 0.45 0.74;0.85 0.33 0.10;0.93 0.69 0.13]; h=gobjects(3,1); x=1:height(cond);
for p=1:3, h(p)=plot3(ax,x,p*ones(size(x)),zNorm(p,:),'-o','LineWidth',1.2,'MarkerSize',3.2,'Color',cc(p,:),'MarkerFaceColor','w'); end
xlabel(ax,'工况','FontSize',9); ylabel(ax,'测点','FontSize',9); zlabel(ax,'归一化RMS','FontSize',9); spd=unique(cond.speed); tickIdx=zeros(numel(spd),1); tickLab=strings(numel(spd),1); for i=1:numel(spd), ids=find(cond.speed==spd(i)); tickIdx(i)=ids(1); tickLab(i)=string(spd(i)); end; xticks(ax,tickIdx); xticklabels(ax,tickLab); yticks(ax,1:3); yticklabels(ax,posShort); zlim(ax,[0 1.05]); xlim(ax,[1 height(cond)]); ylim(ax,[0.8 3.2]); view(ax,[-35 20]); camproj(ax,'orthographic'); pbaspect(ax,[2.8 0.9 0.65]); set(ax,'FontSize',8,'TickDir','in','LineWidth',0.75,'Box','off','XGrid','off','YGrid','off','ZGrid','off'); title(ax,'三测点振动','FontSize',10.5,'FontWeight','normal'); legend(ax,h,posShort,'Location','southoutside','Orientation','horizontal','FontSize',7.5,'Box','off'); exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function hide3DFrameLines(ax)
try
    ax.XRuler.Axle.Visible = 'off';
    ax.YRuler.Axle.Visible = 'off';
    ax.ZRuler.Axle.Visible = 'off';
catch
    % Older MATLAB releases may not expose ruler axle handles.
end
end
function drawBottom3DFrame(ax, xMin, xMax, yMin, yMax, zMin, zMax)
frameColor = [0.42 0.42 0.42];
lineArgs = {'Color', frameColor, 'LineWidth', 0.75, 'HandleVisibility', 'off'};
plot3(ax, [xMin xMax], [yMin yMin], [zMin zMin], '-', lineArgs{:});
plot3(ax, [xMin xMax], [yMax yMax], [zMin zMin], '-', lineArgs{:});
plot3(ax, [xMin xMin], [yMin yMax], [zMin zMin], '-', lineArgs{:});
plot3(ax, [xMin xMin], [yMax yMax], [zMin zMax], '-', lineArgs{:});
xlim(ax, [xMin xMax]);
ylim(ax, [yMin yMax]);
zlim(ax, [zMin zMax]);
end
function drawChapter43SubplotFrame(ax, xMin, xMax, yMin, yMax, zMin, zMax)
frameColor = [0.46 0.46 0.46];
lineArgs = {'Color', frameColor, 'LineWidth', 0.8, 'HandleVisibility', 'off'};
plot3(ax, [xMin xMax], [yMin yMin], [zMin zMin], '-', lineArgs{:});
plot3(ax, [xMin xMin], [yMin yMax], [zMin zMin], '-', lineArgs{:});
plot3(ax, [xMin xMin], [yMax yMax], [zMin zMax], '-', lineArgs{:});
xlim(ax, [xMin xMax]);
ylim(ax, [yMin yMax]);
zlim(ax, [zMin zMax]);
end
function saveChapter43ConditionInfluence(det, feat, outPath)
feat.vibration_combined_rms=sqrt(feat.vibration_1_rms.^2+feat.vibration_2_rms.^2); baseDet=det(:,{'point','speed','opening','filename','burst_time','final_pressure_drop_pct','final_flow_increase_pct'}); baseFeat=feat(:,{'point','speed','opening','filename','vibration_combined_rms','svmd_energy_mean'}); joined=innerjoin(baseDet,baseFeat,'Keys',{'point','speed','opening','filename'}); spd=unique(joined.speed); opn=unique(joined.opening);
fig=paperFigure([17.2 12.5]); tl=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact'); plotConditionHeatmap(nexttile(tl),joined,spd,opn,'burst_time','BT'); plotConditionHeatmap(nexttile(tl),joined,spd,opn,'final_pressure_drop_pct','PD'); plotConditionHeatmap(nexttile(tl),joined,spd,opn,'final_flow_increase_pct','FI'); plotConditionHeatmap(nexttile(tl),joined,spd,opn,'vibration_combined_rms','V-RMS'); title(tl,'工况影响','FontSize',10.5,'FontWeight','normal'); exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function saveChapter43CorrelationMatrix(det, feat, outPath)
condTbl = buildChapter34ConditionTable(det, feat);
predictorNames = {'Speed','Opening','F_RMS','N_RMS','R_RMS'};
responseNames = {'BT','PD','FI'};
xLabels = {'转速','开度','F-RMS','N-RMS','R-RMS'};
legendLabels = {'BT','PD','FI'};
corrBars = nan(numel(predictorNames), numel(responseNames));
for i = 1:numel(predictorNames)
    for j = 1:numel(responseNames)
        corrBars(i,j) = pearsonPair(condTbl.(predictorNames{i}), condTbl.(responseNames{j}));
    end
end
fig=paperFigure([17.2 10.5]); ax=axes(fig); hold(ax,'on');
hb=bar(ax,corrBars,'grouped');
yline(ax,0,'-','Color',[.35 .35 .35],'LineWidth',.7,'HandleVisibility','off');
xlim(ax,[.5 5.5]); ylim(ax,[-1 1]); yticks(ax,-1:.5:1); xticks(ax,1:5); xticklabels(ax,xLabels);
paperAxes(ax,8); xlabel(ax,'因子','FontSize',9); ylabel(ax,'相关系数 r','FontSize',9);
title(ax,'相关性','FontSize',10.5,'FontWeight','normal');
legend(ax,hb,legendLabels,'Location','southoutside','Orientation','horizontal','FontSize',7.5,'Box','off');
exportgraphics(fig,outPath,'Resolution',600); close(fig);
end

function saveChapter43PressureFlowThreePositionRelation(det, feat, outPath)
condTbl = buildChapter34ConditionTable(det, feat);
cond = table(condTbl.Speed, condTbl.Opening, 'VariableNames', {'speed','opening'});
mat = [condTbl.PD condTbl.FI condTbl.F_RMS condTbl.N_RMS condTbl.R_RMS];
matNorm = normalizeMatrix(mat);
metricLabels = {'PD','FI','F-RMS','N-RMS','R-RMS'};
metricColors = [0.00 0.45 0.74;0.85 0.33 0.10;0.93 0.69 0.13;0.49 0.18 0.56;0.47 0.67 0.19];
fig = paperFigure([17.2 10.8]);
ax = axes(fig); hold(ax,'on');
x = 1:height(cond);
y = 1:numel(metricLabels);
h = gobjects(numel(metricLabels),1);
for k = 1:numel(metricLabels)
    z = matNorm(:,k)';
    h(k) = plot3(ax, x, y(k) * ones(size(x)), z, '-o', ...
        'LineWidth', 1.25, 'MarkerSize', 3.8, 'Color', metricColors(k,:), ...
        'MarkerFaceColor', 'w', 'DisplayName', metricLabels{k});
    patch(ax, [x fliplr(x)], [y(k)*ones(size(x)) fliplr(y(k)*ones(size(x)))], [z zeros(size(z))], ...
        metricColors(k,:), 'FaceAlpha', 0.07, 'EdgeColor', 'none', 'HandleVisibility', 'off');
end
spd = unique(cond.speed);
tickIdx = zeros(numel(spd),1);
tickLab = strings(numel(spd),1);
for i = 1:numel(spd)
    ids = find(cond.speed == spd(i));
    tickIdx(i) = ids(1);
    tickLab(i) = sprintf('%g-%g', cond.speed(ids(1)), cond.opening(ids(1)));
end
xlabel(ax,'工况','FontSize',9);
ylabel(ax,'指标','FontSize',9);
zlabel(ax,'归一化值','FontSize',9);
xticks(ax,tickIdx);
xticklabels(ax,tickLab);
yticks(ax,y);
yticklabels(ax,metricLabels);
xlim(ax,[1 height(cond)]);
ylim(ax,[0.7 numel(metricLabels)+0.3]);
zlim(ax,[0 1.05]);
view(ax,[-42 22]);
camproj(ax,'orthographic');
pbaspect(ax,[2.7 1.0 0.85]);
set(ax,'FontSize',8,'TickDir','in','TickLength',[0.012 0.012],'LineWidth',0.75, ...
    'Box','off','XGrid','off','YGrid','off','ZGrid','off');
hide3DFrameLines(ax);
drawBottom3DFrame(ax,1,height(cond),1,numel(metricLabels),0,1.05);
legend(ax,h,metricLabels,'Location','southoutside','Orientation','horizontal', ...
    'NumColumns',5,'FontSize',7.3,'Box','off');
title(ax,'多源响应','FontSize',10.5,'FontWeight','normal');
exportgraphics(fig,outPath,'Resolution',600);
close(fig);
end

function saveChapter43ThreePositionVibration(feat, outPath)
posFeat = buildThreePositionFeatureTable(feat);
positions = {'固定测点','近爆管点测点','远爆管点测点'};
short = {'FP','NP','RP'};
speeds = unique(posFeat.speed);
openings = unique(posFeat.opening);
allZ = nan(numel(speeds), numel(openings), numel(positions));
for p = 1:numel(positions)
    sub = posFeat(posFeat.position == string(positions{p}), :);
    allZ(:,:,p) = conditionMatrix(sub, speeds, openings, 'rms');
end
zMax = max(allZ, [], 'all', 'omitnan');
if ~isfinite(zMax) || zMax <= 0
    zMax = 1;
end
fig = paperFigure([17.2 7.2]);
tl = tiledlayout(fig,1,3,'TileSpacing','compact','Padding','compact');
for p = 1:numel(positions)
    ax = nexttile(tl);
    z = allZ(:,:,p);
    bh = bar3(ax, z, 0.72);
    for k = 1:numel(bh)
        zdata = bh(k).ZData;
        bh(k).CData = zdata;
        bh(k).FaceColor = 'interp';
        bh(k).EdgeColor = [0.35 0.35 0.35];
        bh(k).LineWidth = 0.45;
    end
    colormap(ax, parula);
    xticks(ax, 1:numel(openings));
    xticklabels(ax, string(openings));
    yticks(ax, 1:numel(speeds));
    yticklabels(ax, string(speeds));
    xlabel(ax, '开度/%', 'FontSize', 8.8);
    ylabel(ax, '转速/Hz', 'FontSize', 8.8);
    zlabel(ax, 'RMS', 'FontSize', 8.8);
    title(ax, sprintf('(%c) %s', char('a'+p-1), short{p}), 'FontSize', 9.2, 'FontWeight', 'normal');
    zlim(ax, [0 zMax * 1.10]);
    view(ax, [-38 24]);
    camproj(ax, 'orthographic');
    pbaspect(ax, [1.15 1.0 0.8]);
    set(ax, 'FontSize', 7.8, 'TickDir', 'in', 'TickLength', [0.012 0.012], ...
        'LineWidth', 0.75, 'Box', 'off', 'XGrid', 'off', 'YGrid', 'off', 'ZGrid', 'off');
end
cb = colorbar(gca, 'eastoutside');
cb.Layout.Tile = 'east';
cb.FontSize = 7.6;
cb.Label.String = 'RMS';
title(tl,'振动工况响应','FontSize',10.5,'FontWeight','normal');
exportgraphics(fig,outPath,'Resolution',600);
close(fig);
end

function saveChapter43ThreePositionSpeedOpeningWaterfall(feat, outPath)
posFeat = buildThreePositionFeatureTable(feat);
positions = {'固定测点','近爆管点测点','远爆管点测点'};
speeds = unique(posFeat.speed);
openings = unique(posFeat.opening);
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1600 720]);
tl = tiledlayout(1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
for p = 1:numel(positions)
    ax = nexttile;
    sub = posFeat(posFeat.position == string(positions{p}), :);
    z = conditionMatrix(sub, speeds, openings, 'rms');
    zNorm = normalizeMatrixGlobal(z);
    hold(ax, 'on'); grid(ax, 'off'); box(ax, 'off');
    speedColors = turbo(numel(speeds));
    for i = 1:numel(speeds)
        zRow = zNorm(i, :);
        valid = isfinite(zRow);
        if nnz(valid) < 2
            continue;
        end
        xRow = openings(valid)';
        zRow = zRow(valid);
        zRow = zRow(:)';
        yRow = speeds(i) * ones(size(xRow));
        patch(ax, [xRow fliplr(xRow)], [yRow fliplr(yRow)], [zRow zeros(size(zRow))], ...
            speedColors(i, :), 'FaceAlpha', 0.22, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        stemColor = 0.65 * speedColors(i, :) + 0.35 * [1 1 1];
        for j = 1:numel(xRow)
            plot3(ax, [xRow(j) xRow(j)], [yRow(j) yRow(j)], [0 zRow(j)], '-', ...
                'Color', stemColor, 'LineWidth', 0.45, 'HandleVisibility', 'off');
        end
        plot3(ax, xRow, yRow, zRow, '-', 'Color', speedColors(i, :), 'LineWidth', 2.2);
    end
    colormap(ax, turbo);
    cb = colorbar(ax, 'southoutside');
    cb.Label.String = '归一化值';
    xlabel(ax, '开度/%'); ylabel(ax, '转速/Hz'); zlabel(ax, '归一化RMS');
    xticks(ax, openings); yticks(ax, speeds);
    xlim(ax, [min(openings), max(openings)]);
    ylim(ax, [min(speeds), max(speeds)]);
    zlim(ax, [0 1.05]);
    view(ax, [-38 18]);
    camproj(ax, 'orthographic');
    pbaspect(ax, [1.25 1.0 0.48]);
    set(ax, 'TickDir', 'in', 'TickLength', [0.018 0.018], ...
        'XGrid', 'off', 'YGrid', 'off', 'ZGrid', 'off', 'Box', 'off', 'LineWidth', 0.8, 'FontSize', 8);
    hide3DFrameLines(ax);
    drawChapter43SubplotFrame(ax, min(openings), max(openings), min(speeds), max(speeds), 0, 1.05);
    ax.Color = 'w';
    title(ax, sprintf('%s', positions{p}), 'Interpreter', 'none');
end
title(tl, '三测点振动');
exportgraphics(fig, outPath, 'Resolution', 600);
close(fig);
end

function fig = paperFigure(sz)
% Draw at about twice final single-column width; insert exported image at 8.63 cm.
fig=figure('Visible','off','Color','w','Units','centimeters','Position',[2 2 sz(1) sz(2)]);
try
    set(fig,'DefaultAxesFontName','Microsoft YaHei','DefaultTextFontName','Microsoft YaHei');
catch
end
end

function paperAxes(ax, fs)
set(ax,'FontSize',fs,'TickDir','in','TickLength',[0.010 0.010],'LineWidth',0.75,'Box','off','Layer','top','XGrid','off','YGrid','off');
end

function plotConditionHeatmap(ax, tbl, speeds, openings, valueName, titleText)
mat=nan(numel(speeds),numel(openings)); for i=1:numel(speeds), for j=1:numel(openings), mask=tbl.speed==speeds(i)&tbl.opening==openings(j); mat(i,j)=mean(tbl.(valueName)(mask),'omitnan'); end, end
imagesc(ax,openings,speeds,mat); set(ax,'YDir','normal'); colormap(ax,parula); cb=colorbar(ax,'eastoutside'); cb.FontSize=7; xticks(ax,openings); yticks(ax,speeds); xlabel(ax,'开度/%','FontSize',8.5); ylabel(ax,'转速/Hz','FontSize',8.5); title(ax,titleText,'FontSize',9,'FontWeight','normal'); paperAxes(ax,7.5); box(ax,'on');
for i=1:numel(speeds), for j=1:numel(openings), if isfinite(mat(i,j)), text(ax,openings(j),speeds(i),sprintf('%.2f',mat(i,j)),'HorizontalAlignment','center','VerticalAlignment','middle','Color','w','FontSize',6.5,'FontWeight','bold'); end, end, end
end

function mat = conditionMatrix(tbl, speeds, openings, valueName)
mat = nan(numel(speeds), numel(openings));
for i = 1:numel(speeds)
    for j = 1:numel(openings)
        mask = tbl.speed == speeds(i) & tbl.opening == openings(j);
        mat(i, j) = mean(tbl.(valueName)(mask), 'omitnan');
    end
end
end

function m = normalizeMatrixGlobal(m)
mn = min(m, [], 'all', 'omitnan');
mx = max(m, [], 'all', 'omitnan');
den = mx - mn;
if ~isfinite(den) || den <= 1e-12
    m = zeros(size(m));
else
    m = (m - mn) ./ den;
end
m(isnan(m)) = 0;
end

function pair = pointPairFeatureTable(feat, p1, p2)
a = feat(feat.point == p1, {'speed','opening','filename','vibration_combined_rms','svmd_energy_mean','vibration_combined_energy_high_band_ratio'});
b = feat(feat.point == p2, {'speed','opening','filename','vibration_combined_rms','svmd_energy_mean','vibration_combined_energy_high_band_ratio'});
pair = innerjoin(a, b, 'Keys', {'speed','opening','filename'});
pair.vib_rms_delta_norm = normalizeDifference(pair.vibration_combined_rms_a, pair.vibration_combined_rms_b);
pair.svmd_energy_delta_norm = normalizeDifference(pair.svmd_energy_mean_a, pair.svmd_energy_mean_b);
pair.high_ratio_delta_norm = normalizeDifference(pair.vibration_combined_energy_high_band_ratio_a, pair.vibration_combined_energy_high_band_ratio_b);
pair = sortrows(pair, {'speed','opening'});
end

function d = normalizeDifference(a, b)
allv = [a; b];
mn = min(allv, [], 'omitnan');
mx = max(allv, [], 'omitnan');
den = mx - mn;
if ~isfinite(den) || den <= 1e-12
    d = zeros(size(a));
else
    d = ((b - mn) ./ den) - ((a - mn) ./ den);
end
end
function m = normalizeMatrix(m)
mn = min(m, [], 1, 'omitnan');
mx = max(m, [], 1, 'omitnan');
den = mx - mn;
den(den == 0) = NaN;
m = (m - mn) ./ den;
m(isnan(m)) = 0;
end

function [labels, series] = pivotPointSeries(det, valueName)
base = unique(det(:, {'speed','opening'}), 'rows');
base = sortrows(base, {'speed','opening'});
labels = strcat(string(base.speed), '-', string(base.opening));
points = unique(det.point, 'stable');
series = struct();
for i = 1:numel(points)
    sub = det(det.point == points(i), {'speed','opening',valueName});
    merged = outerjoin(base, sub, 'Keys', {'speed','opening'}, 'MergeKeys', true, 'Type', 'left');
    field = matlab.lang.makeValidName(char(points(i)));
    series.(field) = merged.(valueName);
end
end

function pair = pointPairTable(det, p1, p2)
a = det(det.point == p1, {'speed','opening','filename','burst_time','final_pressure_drop_pct'});
b = det(det.point == p2, {'speed','opening','filename','burst_time','final_pressure_drop_pct'});
pair = innerjoin(a, b, 'Keys', {'speed','opening','filename'});
pair.burst_delta = pair.burst_time_b - pair.burst_time_a;
pair.drop_delta = pair.final_pressure_drop_pct_b - pair.final_pressure_drop_pct_a;
pair = sortrows(pair, {'speed','opening'});
end

function saveLineChart(path, titleText, subtitle, labels, series, yLabel, notes)
fields = fieldnames(series);
vals = [];
for i = 1:numel(fields)
    vals = [vals; series.(fields{i})(:)]; %#ok<AGROW>
end
[yMin, yMax] = niceLimits(vals);
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1500 850]);
hold on; grid on; box on;
for i = 1:numel(fields)
    plot(series.(fields{i}), '-o', 'LineWidth', 2.2, 'MarkerSize', 5);
end
ylim([yMin yMax]);
if numel(labels) <= 1
    xlim([0.5 1.5]);
else
    xlim([1 numel(labels)]);
end
xticks(1:numel(labels)); xticklabels(labels); xtickangle(45);
ylabel(yLabel); xlabel('工况（转速-开度）');
if strlength(string(subtitle)) == 0
    title(titleText);
else
    title({titleText, subtitle});
end
legend(displayLegendLabels(fields), 'Location', 'northeast', 'Interpreter', 'none');
exportgraphics(fig, path, 'Resolution', 220);
close(fig);
end


function labels = displayLegendLabels(fields)
labels = fields;
for i = 1:numel(fields)
    f = string(fields{i});
    if contains(f, "x__1") || contains(f, "_1") && ~contains(f, "delta")
        labels{i} = '第一组实验（含近爆管点测点）';
    elseif contains(f, "x__2") || contains(f, "_2") && ~contains(f, "delta")
        labels{i} = '第二组实验（含远爆管点测点）';
    end
end
end
function saveHeatmap(path, titleText, subtitle, rowLabels, colLabels, data, notes)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1500 850]);
h = heatmap(colLabels, rowLabels, data, 'Colormap', parula, 'ColorLimits', [0 1]);
if strlength(string(subtitle)) == 0
    h.Title = titleText;
else
    h.Title = sprintf('%s\\n%s', titleText, subtitle);
end
h.XLabel = '特征指标';
h.YLabel = '转速';
exportgraphics(fig, path, 'Resolution', 220);
close(fig);
end

function saveGroupedBarChart(path, titleText, subtitle, labels, legendLabels, data, yLabel, notes)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1500 850]);
hb = bar(data, 'grouped'); grid on; box on;
xticks(1:numel(labels)); xticklabels(labels); xtickangle(45);
ylabel(yLabel); xlabel('工况（转速-开度）');
if strlength(string(subtitle)) == 0
    title(titleText);
else
    title({titleText, subtitle});
end
if numel(hb) == numel(legendLabels)
    legend(hb, legendLabels, 'Location', 'northeast', 'Interpreter', 'none');
else
    legend(hb, legendLabels(1:numel(hb)), 'Location', 'northeast', 'Interpreter', 'none');
end
exportgraphics(fig, path, 'Resolution', 220);
close(fig);
end

function [lo, hi] = niceLimits(values)
values = values(isfinite(values));
if isempty(values)
    lo = 0; hi = 1; return;
end
lo = min(values); hi = max(values);
if abs(hi - lo) < 1e-12
    pad = max(abs(hi) * 0.1, 1);
else
    pad = (hi - lo) * 0.08;
end
lo = lo - pad; hi = hi + pad;
end


















