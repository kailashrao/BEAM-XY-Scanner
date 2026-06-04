% pio_multi_trigger_analysis.m (test3.m)
% Updated 6/4/2026 by Kailash Rao

% Works for T0006 (PIO)

% PIO takes negligible time (ns) to execute compared to the oscilloscope's current resolution of 1.6us 
% Since delay is negligible, we assume that the Pico's high voltage threshold (PHVT)
% is the same point as where the trigger edge rises (not true for T0002-T0005)

% Strategy: Measure time it takes for encoder signal to reach PHVT = Trigger
% total delay = rise time to PHVT/Trigger (10% to PHVT/Trigger)

%% Multi-Trigger Coherent Latency & Statistics Analyzer
clear; clc; close all;

% --- Configuration ---
[fileName, pathName] = uigetfile('data/*.CSV', 'Select a Data Set');
csvFileName = fullfile(pathName, fileName);
lookback_samples = 250;        
lookforward_samples = 50;      

% --- Setup Import Settings ---
opts = delimitedTextImportOptions("NumVariables", 5);
opts.DataLines = [17, Inf]; 
opts.Delimiter = ",";
opts.VariableNames = ["Time", "CH1", "CH1_Peak", "CH2", "CH2_Peak"];
opts.VariableTypes = ["double", "double", "double", "double", "double"];

fprintf('Importing continuous time-series data from: %s\n', csvFileName);
data = readtable(csvFileName, opts);
time = data.Time;
ch1_input = data.CH1;    
ch2_trigger = data.CH2;  
dt = mean(diff(time));

%% 1. Vectorized Rising-Edge Detection for ALL Channel 2 Triggers
ch2_low = min(ch2_trigger);
ch2_high = max(ch2_trigger);
ch2_mid = ch2_low + 0.50 * (ch2_high - ch2_low);

all_trigger_indices = find(ch2_trigger(2:end) >= ch2_mid & ch2_trigger(1:end-1) < ch2_mid) + 1;
num_triggers = length(all_trigger_indices);

fprintf('Detected %d distinct radar trigger pulses in dataset.\n', num_triggers);

if num_triggers == 0
    error('No radar triggers detected. Verify Channel 2 voltage thresholds.');
end

%% 2. Loop Through Every Trigger Pulse to Process Latencies
trigger_number = (1:num_triggers)';
rc_time_constants_us = zeros(num_triggers, 1);
time_to_pico_high_us = zeros(num_triggers, 1); 
pio_delays_us = zeros(num_triggers, 1);
total_delays_us = zeros(num_triggers, 1);
trip_voltages = zeros(num_triggers, 1);

for i = 1:num_triggers
    idx_trigger = all_trigger_indices(i);
    t_trigger_rise = time(idx_trigger);
    
    idx_search_start = max(1, idx_trigger - lookback_samples);
    idx_search_end = min(length(time), idx_trigger + lookforward_samples);
    search_window_ch1 = ch1_input(idx_search_start:idx_search_end);
    search_window_time = time(idx_search_start:idx_search_end);
    
    idx_trigger_rel = idx_trigger - idx_search_start + 1;
    
    % DYNAMIC FIX: Measure actual hardware trip voltage for this pulse
    v_pico_high_threshold_local = ch1_input(idx_trigger);
    trip_voltages(i) = v_pico_high_threshold_local;
    
    idx_last_low = find(search_window_ch1(1:idx_trigger_rel) < v_pico_high_threshold_local, 1, 'last');
    if isempty(idx_last_low)
        idx_local_pico_high = idx_trigger_rel;
    else
        idx_local_pico_high = idx_last_low + 1;
    end
    t_pico_registered_high = search_window_time(idx_local_pico_high);
    
    ch1_high_local = max(search_window_ch1);
    ch1_low_local = min(search_window_ch1);
    v_rise_10 = ch1_low_local + 0.10 * (ch1_high_local - ch1_low_local);
    v_rise_90 = ch1_low_local + 0.90 * (ch1_high_local - ch1_low_local);
    
    idx_local_rise_start = find(search_window_ch1(1:idx_trigger_rel) < v_rise_10, 1, 'last') + 1;
    t_encoder_rise_start = search_window_time(idx_local_rise_start);
    
    idx_relative_rise_end = find(search_window_ch1(idx_local_rise_start:end) >= v_rise_90, 1, 'first');
    if isempty(idx_relative_rise_end)
        idx_local_rise_end = length(search_window_ch1); 
    else
        idx_local_rise_end = idx_local_rise_start + idx_relative_rise_end - 1;
    end
    t_encoder_rise_end = search_window_time(idx_local_rise_end);
    
    rc_time_constants_us(i) = (t_encoder_rise_end - t_encoder_rise_start) * 1e6;
    time_to_pico_high_us(i) = (t_pico_registered_high - t_encoder_rise_start) * 1e6; 
    pio_delays_us(i)        = (t_trigger_rise - t_pico_registered_high) * 1e6;
    total_delays_us(i)      = (t_trigger_rise - t_encoder_rise_start) * 1e6;
end

%% 3. Generate and Display the Trial Summary Table
TrialTable = table(trigger_number, trip_voltages, rc_time_constants_us, time_to_pico_high_us, pio_delays_us, total_delays_us, ...
    'VariableNames', {'Pulse_ID', 'Trip_Voltage_V', 'RC_Rise_Time_us', 'Time_To_Pico_High_us', 'PIO_Delay_us', 'Total_Delay_us'});

fprintf('\n======================= DATASET SUMMARY TABLE =======================\n');
disp(TrialTable);

%% 4. Compute and Aggregate Core Statistical Metrics
stats_labels = {'Mean'; 'Median'; 'Max'; 'Min'; 'StdDev'};
stats_rc     = [mean(rc_time_constants_us); median(rc_time_constants_us); max(rc_time_constants_us); min(rc_time_constants_us); std(rc_time_constants_us)];
stats_t2high = [mean(time_to_pico_high_us); median(time_to_pico_high_us); max(time_to_pico_high_us); min(time_to_pico_high_us); std(time_to_pico_high_us)]; 
stats_pio   = [mean(pio_delays_us); median(pio_delays_us); max(pio_delays_us); min(pio_delays_us); std(pio_delays_us)];
stats_total  = [mean(total_delays_us); median(total_delays_us); max(total_delays_us); min(total_delays_us); std(total_delays_us)];

StatsTable = table(stats_labels, stats_rc, stats_t2high, stats_pio, stats_total, ...
    'VariableNames', {'Metric', 'RC_Rise_Time_us', 'Time_To_Pico_High_us', 'PIO_Delay_us', 'Total_Delay_us'});

fprintf('======================= AGGREGATED STATISTICS =======================\n');
disp(StatsTable);

%% 5. Optional: Plot Jitter Distribution Profile
figure('Name', 'Radar Trigger Jitter Analysis', 'Color', 'w');
histogram(total_delays_us, 10, 'FaceColor', 'r', 'EdgeColor', 'w');
grid on;
xlabel('Total Alignment Latency (\mu s)');
ylabel('Occurrences / Pulses');
title(sprintf('Coherent Trigger Jitter Distribution Profile (N = %d)', num_triggers));