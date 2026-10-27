# AM-MEFD-SVMD

**State Recognition and Feature Extraction of Burst Vibration Tests in Water Supply Pipelines**

**Algorithm Description:**

According to the current project document, the chapter titles and main research contents are as follows:

**Chapter 2: AM-MEFD/SVMD Steady-Unsteady State Recognition and Feature Extraction Method**

This chapter focuses on method and algorithm construction, with main research contents including:

* Reading raw signals of pressure, flow rate, and vibration, followed by filtering and multi-source signal construction.
* Establishing an adaptive steady-state baseline before the pipe burst, using the median and MAD (Median Absolute Deviation) to describe the steady-state level and fluctuation scale.
* Decomposing pressure and synthesized vibration signals into multiple modes using SVMD (Successive Variational Mode Decomposition) and calculating the energy of each mode.
* Extracting sliding time-domain features using a 0.20 s window and a 0.05 s step size, and frequency-domain features using a 1.00 s window.
* Constructing the AM-MEFD comprehensive transition index by integrating pressure drop, pressure gradient, flow rate change, vibration energy, and SVMD modal energy.
* Identifying the boundary of the transition from steady-state to unsteady-state (i.e., the pipe burst response moment) through adaptive thresholds and consecutive window criteria.
* Dividing the signal into steady-state segments, short-term unsteady-state segments, and post-burst final stable segments.
* Extracting features such as mean, standard deviation, RMS, peak-to-peak value, skewness, kurtosis, permutation entropy, dominant frequency, spectral centroid, and band energy.
* Performing hydraulic mechanism validation on the recognition results using pressure drop and flow rate changes.
* Mapping vibration signals from the two groups of experiments into fixed measurement points, near-burst points, and far-burst points.

The core objective of this chapter is:

* To establish a steady-unsteady state boundary recognition and feature extraction method that integrates pressure, flow rate, vibration, and SVMD modal energy.

**Chapter 4: Multi-source Response and Operating Condition Impact Analysis of Pipe Bursts Based on AM-MEFD/SVMD**

This chapter focuses on result analysis and engineering regularity research, with main research contents including:

* Analyzing the time-history responses of pressure, flow rate, and vibration signals before and after the pipe burst, and comparing the response synchronicity of different signals to the burst event.
* Taking the identified pipe burst moment as time zero, conducting time alignment and normalization comparison for data under different operating conditions.
* Selecting representative operating conditions to display the local response processes of pressure, flow rate, and different vibration measurement points near the burst boundary.
* Performing SVMD time-domain decomposition and spectral analysis on steady-state and unsteady-state vibration signals to study the dominant frequency, energy ratio, and frequency band structure changes of each mode.
* Comparing vibration features such as RMS, peak-to-peak value, and standard deviation among the fixed measurement point, near-burst point, and far-burst point.
* Analyzing the propagation and attenuation laws of vibration disturbances as a function of measurement point location, and evaluating the sensitivity of different measurement points to pipe bursts.
* Studying the effects of rotational speed and valve opening on the pipe burst response time, pressure drop, flow rate change, and vibration intensity.
* Analyzing the correlation relationships among pressure, flow rate, vibration, and operating parameters.
* Verifying the consistency and engineering rationality of the AM-MEFD/SVMD recognition results using all operating conditions.

The core objective of this chapter is:

* Based on the method proposed in Chapter 2, to reveal the unsteady response characteristics of multi-source signals during the pipe burst process, as well as the influence laws of measurement point location, rotational speed, and valve opening on the pipe burst response.

The program data is divided into Vibration Point 1 and Vibration Point 2, where data1-data4 of Vibration Point 1 constitute the complete raw data for Vibration Point 1, and data1-data4 of Vibration Point 2 constitute the complete data for Vibration Point 2.

---

**Measurement Point Layout and Data Acquisition**

Pressure measurement points are arranged at different positions along the pipeline, with a total of 8 pressure sensors set up to capture the formation, propagation, and attenuation processes of pressure waves before and after the pipe burst. Flow measurement is completed using an ultrasonic flowmeter, which is mainly used to record the trend of flow rate changes in the pipe before and after the burst event and conduct time-correlated analysis with pressure and vibration responses. Vibration measurements are arranged on the outer side of the pipe wall, focusing on collecting the local structural vibration response induced by burst disturbances.

Due to limitations in data acquisition channels and sensor layout conditions, a phased measurement scheme is adopted for vibration measurement points. Both groups of experiments retain Vibration Point 1, whose position remains unchanged across the two groups and serves as a reference measurement point for vibration response; Vibration Point 2 is arranged closer to the pipe burst point at a distance of approximately 0.4 m; Vibration Point 3 is arranged farther from the pipe burst point at a distance of approximately 2.0 m. The two groups of experiments respectively collect the synchronous vibration responses of Vibration Point 1 with Vibration Point 2, and Vibration Point 1 with Vibration Point 3, ultimately forming 3 vibration observation points. Since the 3 positions are not sampled synchronously in the same experiment, subsequent comparisons are only used to analyze the differences in measurement point responses under identical operating condition settings, and strict synchronous transient propagation processes are not inferred from this. During the experiment, pressure, flow rate, and pipe wall vibration signals are simultaneously collected by the same data acquisition system, with a unified time base applied to all channels. The sampling frequency is set to 1000 Hz for all channels, and the single recording duration is 30 s, to fully cover stable operation, burst triggering, and unsteady response processes. Before formal acquisition, zero checks and signal calibrations are performed on all channels, and recording begins only after the outputs of pressure, flow rate, and vibration stabilize, thereby reducing the impact of channel drift and accidental noise on boundary recognition and feature statistics.

The experiment takes centrifugal pump rotational speed and inlet valve opening as the main control variables. The centrifugal pump rotational speed is set to 30 Hz, 35 Hz, 40 Hz, 45 Hz, and 50 Hz, and the inlet valve opening is set to 40%, 60%, 80%, and 100%. Combining these two types of variables results in a total of 20 operating conditions, as shown in Table 2. Different rotational speeds correspond to different water supply power levels, and different valve openings correspond to different pipeline resistance conditions. Through full-condition combinations, the variation laws of pipe burst unsteady responses with operating parameters can be analyzed.
