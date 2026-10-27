function generate_am_mefd_section_outputs(varargin)
%GENERATE_AM_MEFD_SECTION_OUTPUTS Generate AM-MEFD section figures from raw XLSX files.
%
% This MATLAB version re-runs the AM-MEFD base algorithm from original XLSX
% files and exports figures for:
%   2.2 Steady/nonstationary boundary identification
%   2.3 Time-domain feature extraction
%   2.4 Frequency-domain feature extraction
%   2.5 Pressure-signal auxiliary validation
%
% Usage:
%   generate_am_mefd_section_outputs
%   generate_am_mefd_section_outputs('Workers', 4)
%   generate_am_mefd_section_outputs('Root', 'F:\path\to\data')

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
makeFigures(det, feat, cfg.outputDir);
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
p.parse(varargin{:});
cfg = p.Results;
cfg.root = char(cfg.Root);
if strlength(string(cfg.OutputDir)) == 0
    cfg.outputDir = fullfile(cfg.root, 'outputs_am_mefd', 'section_outputs');
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
cfg.windowSec = 0.20;
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
    if contains(lower(f), lower(outputDir)) || contains(lower(f), lower(fullfile(rootDir, 'outputs_')))
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

function makeFigures(det, feat, outputDir)
[labels, burstSeries] = pivotPointSeries(det, 'burst_time');
saveLineChart(fullfile(outputDir, 'section_2_2_boundary_identification.png'), ...
    '稳态与非稳态的边界识别', ...
    '', ...
    labels, burstSeries, '爆管响应时刻 (s)', ...
    {sprintf('爆管时刻范围：%.3fs - %.3fs', min(det.burst_time), max(det.burst_time)), sprintf('平均爆管时刻：%.3fs', mean(det.burst_time)), '稳态终点 = 非稳态起点 = 爆管响应时刻；两组实验均参与边界识别'});

posFeat = buildThreePositionFeatureTable(feat);
speeds = unique(feat.speed);
positions = {'固定测点','近爆管点测点','远爆管点测点'};

baseTd = groupsummary(feat, 'speed', 'mean', {'pressure_mean_rms','flow_rms'});
tdMat = [baseTd.mean_pressure_mean_rms, baseTd.mean_flow_rms, meanPositionMatrix(posFeat, speeds, positions, 'rms')];
tdNorm = normalizeMatrix(tdMat);
saveHeatmap(fullfile(outputDir, 'section_2_3_time_domain_features.png'), ...
    '时域特征提取', '', ...
    strcat('转速 ', string(speeds)), {'压力RMS','流量RMS','固定测点RMS','近爆管点RMS','远爆管点RMS'}, tdNorm, ...
    {'特征由 AM-MEFD/SVMD 识别的非稳态段提取', '固定测点来自两组实验1#振动均值，近/远测点来自两组实验2#移动测点'});

baseFd = groupsummary(feat, 'speed', 'mean', {'pressure_mean_spectral_centroid','vibration_combined_energy_high_band_ratio','svmd_energy_mean'});
posCentroid = meanPositionMatrix(posFeat, speeds, positions, 'spectral_centroid');
fdMat = [baseFd.mean_pressure_mean_spectral_centroid, posCentroid, baseFd.mean_vibration_combined_energy_high_band_ratio, baseFd.mean_svmd_energy_mean];
fdNorm = normalizeMatrix(fdMat);
saveHeatmap(fullfile(outputDir, 'section_2_4_frequency_domain_features.png'), ...
    '频域特征提取', '', ...
    strcat('转速 ', string(speeds)), {'压力频谱质心','固定测点频谱质心','近爆管点频谱质心','远爆管点频谱质心','高频能量占比','SVMD模态能量'}, fdNorm, ...
    {'频域特征由 FFT 与 SVMD 模态能量共同表征', '数值采用最小-最大归一化，仅用于可视化比较'});

spd = groupsummary(det, 'speed', 'mean', {'transient_pressure_drop_pct','final_pressure_drop_pct'});
saveGroupedBarChart(fullfile(outputDir, 'section_2_5_pressure_signal_validation.png'), ...
    '压力信号辅助验证', '', ...
    string(spd.speed), {'短时压力降 (%)','最终压力降 (%)'}, ...
    [spd.mean_transient_pressure_drop_pct, spd.mean_final_pressure_drop_pct], '压力下降百分比 (%)', ...
    {sprintf('最终压力降均值：%.2f%%', mean(det.final_pressure_drop_pct)), sprintf('短时压力降均值：%.2f%%', mean(det.transient_pressure_drop_pct)), '最终稳定压力降用于验证非稳态边界识别结果'});

% The experiment-group consistency plot is kept out of Chapter 2 because this
% chapter focuses on method definition rather than repeated-test comparison.
% To restore it later, uncomment the block below.
%
% points = unique(det.point, 'stable');
% if numel(points) >= 2
%     pair = pointPairTable(det, points(1), points(2));
%     saveGroupedBarChart(fullfile(outputDir, 'section_2_5_point_consistency.png'), ...
%         '两组实验一致性辅助验证', '', ...
%         strcat(string(pair.speed), '-', string(pair.opening)), {'爆管时刻差值 (s)','最终压力降差值 (%)'}, ...
%         [pair.burst_delta, pair.drop_delta], '实验组差值', ...
%         {sprintf('平均爆管时刻差值：%.3fs', mean(pair.burst_delta)), sprintf('平均最终压力降差值：%.2f%%', mean(pair.drop_delta)), '注：两类差值单位不同，本图仅用于两组实验一致性辅助对比'});
% end
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

function mat = meanPositionMatrix(posFeat, speeds, positions, valueName)
mat = nan(numel(speeds), numel(positions));
for i = 1:numel(speeds)
    for j = 1:numel(positions)
        mask = posFeat.speed == speeds(i) & posFeat.position == string(positions{j});
        mat(i, j) = mean(posFeat.(valueName)(mask), 'omitnan');
    end
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
set(gca, 'TickLength', [0 0]);
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
text(0.02, -0.22, strjoin(notes, '   |   '), 'Units', 'normalized', 'Interpreter', 'none');
exportgraphics(fig, path, 'Resolution', 220);
close(fig);
end


function labels = displayLegendLabels(fields)
labels = fields;
for i = 1:numel(fields)
    f = string(fields{i});
    if contains(f, "x__1") || contains(f, "_1") && ~contains(f, "delta")
        labels{i} = '第一组实验（2#近爆管点）';
    elseif contains(f, "x__2") || contains(f, "_2") && ~contains(f, "delta")
        labels{i} = '第二组实验（2#远爆管点）';
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
annotation('textbox', [0.08 0.02 0.86 0.06], 'String', strjoin(notes, '   |   '), 'EdgeColor', 'none', 'Interpreter', 'none');
exportgraphics(fig, path, 'Resolution', 220);
close(fig);
end

function saveGroupedBarChart(path, titleText, subtitle, labels, legendLabels, data, yLabel, notes)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1500 850]);
hb = bar(data, 'grouped'); grid on; box on;
set(gca, 'TickLength', [0 0]);
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
text(0.015, 0.965, strjoin(notes, '   |   '), 'Units', 'normalized', 'Interpreter', 'none', 'VerticalAlignment', 'top', 'BackgroundColor', 'w', 'Margin', 2);
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














