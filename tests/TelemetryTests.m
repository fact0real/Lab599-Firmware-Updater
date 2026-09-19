#import <Foundation/Foundation.h>
#import "../Headers/TX500TelemetryEngine.h"

static void Check(BOOL passed, NSString *message) {
    if (!passed) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        printf("Running Telemetry Engine & CAT Protocol tests...\n");

        // 1. Data Defaults and Alarms
        TXTelemetryData *d = [TXTelemetryData new];
        Check(d.voltage == 0.0 && !d.voltageValid, @"Voltage starts unavailable, not at a fabricated nominal value");
        Check(!d.currentValid && !d.temperatureValid, @"Unsupported current and temperature start unavailable");
        Check(!d.rfPowerValid && !d.swrValid && !d.swrMeterValid, @"Power and SWR are not fabricated before CAT replies");
        Check(!d.frequencyValid && !d.modeValid && !d.txStateValid && !d.sMeterValid,
              @"Radio state starts unavailable before CAT replies");
        Check(!d.overvoltageAlert && !d.highSWRAlert && !d.overtempAlert, @"Default has no safety alarms");

        // Overvoltage test (>15.0V)
        d.voltage = 15.5;
        d.voltageValid = YES;
        [d evaluateAlarms];
        Check(d.overvoltageAlert == YES, @"Overvoltage guard triggers at >15.0V");

        // Low voltage test (<9.5V)
        d.voltage = 9.2;
        [d evaluateAlarms];
        Check(d.lowVoltageAlert == YES, @"Low battery guard triggers at <9.5V");

        // High SWR test (>=3.0)
        d.swr = 3.5;
        d.swrValid = YES;
        [d evaluateAlarms];
        Check(d.highSWRAlert == YES, @"High SWR guard triggers at >=3.0");

        // PA Overheat test (>60.0°C)
        d.temperatureCelsius = 65.0;
        d.temperatureValid = YES;
        [d evaluateAlarms];
        Check(d.overtempAlert == YES, @"PA thermal guard triggers at >60°C");

        // Power Source classification tests (BP-500/550 vs External DC)
        d.voltage = 11.8;
        d.voltageValid = YES;
        Check(d.isBatteryPackPowered == YES, @"11.8V is classified as BP-500/550 Battery Pack");
        Check(d.isExternalDCPowered == NO, @"11.8V is not external DC");
        Check([d.powerSourceDescription containsString:@"BP-500/550"], @"Description contains BP-500/550");

        d.voltage = 12.6;
        Check(d.isBatteryPackPowered == YES, @"12.6V (fully charged 3S) is classified as Battery Pack");
        Check(d.isExternalDCPowered == NO, @"12.6V is not external DC");

        d.voltage = 13.8;
        Check(d.isBatteryPackPowered == NO, @"13.8V is not battery pack");
        Check(d.isExternalDCPowered == YES, @"13.8V is classified as External DC");
        Check([d.powerSourceDescription containsString:@"External DC"], @"Description contains External DC");

        // 2. Parser: Kenwood TS-2000 IF; frame
        TXTelemetryData *ifData = [TXTelemetryData new];
        NSString *ifFrame = @"IF00014074000     +0000000001200000 ;";
        BOOL ifOk = [TX500TelemetryEngine parseIFReply:ifFrame intoData:ifData];
        Check(ifOk, @"parseIFReply succeeds on valid Kenwood frame");
        Check(ifData.frequencyHz == 14074000, @"Frequency parsed accurately (14.074 MHz)");
        Check(ifData.isTransmitting == YES, @"TX active state parsed from IF frame");
        Check([ifData.operatingMode isEqualToString:@"USB"], @"USB mode parsed from IF frame");
        Check(ifData.frequencyValid && ifData.modeValid && ifData.txStateValid, @"IF fields are marked valid");

        NSString *ifDig = @"IF00007074000     +0000000000600000 ;";
        [TX500TelemetryEngine parseIFReply:ifDig intoData:ifData];
        Check(ifData.frequencyHz == 7074000, @"Frequency parsed accurately (7.074 MHz)");
        Check(ifData.isTransmitting == NO, @"RX state parsed from IF frame");
        Check([ifData.operatingMode isEqualToString:@"DIG"], @"DIG mode parsed from IF frame");

        // Dedicated commands remain available when IF is unavailable in DIG mode.
        TXTelemetryData *stateData = [TXTelemetryData new];
        Check([TX500TelemetryEngine parseFAReply:@"FA00024889300;" intoData:stateData], @"Physical FA reply parsed");
        Check(stateData.frequencyValid && stateData.frequencyHz == 24889300, @"FA preserves 1 Hz frequency precision");
        Check([TX500TelemetryEngine parseMDReply:@"MD2;" intoData:stateData], @"Physical MD reply parsed");
        Check(stateData.modeValid && [stateData.operatingMode isEqualToString:@"USB"], @"MD2 maps to USB");
        Check([TX500TelemetryEngine parsePTReply:@"PT0;" intoData:stateData], @"Physical PT reply parsed");
        Check(stateData.txStateValid && !stateData.isTransmitting, @"PT0 maps to RX");
        Check([TX500TelemetryEngine parsePCReply:@"PC050;" intoData:stateData], @"Physical PC reply parsed");
        Check(stateData.rfPowerValid && fabs(stateData.rfPowerWatts - 5.0) < 0.01,
              @"PC050 maps to the configured 5.0W setpoint");

        // 3. Parser: RM; meter frames
        TXTelemetryData *rmData = [TXTelemetryData new];
        // Power and SWR are reported as raw 0-30 dots; no invented engineering conversion.
        BOOL rm0Ok = [TX500TelemetryEngine parseRMReply:@"RM00030;" intoData:rmData];
        Check(rm0Ok && rmData.sMeterValid, @"RM0 raw power-meter frame parsed");
        Check(rmData.sMeterDots == 30 && !rmData.rfPowerValid,
              @"RM0 retains 30 raw dots and does not fabricate watts");

        BOOL rm1Ok = [TX500TelemetryEngine parseRMReply:@"RM10015;" intoData:rmData];
        Check(rm1Ok && rmData.swrMeterValid, @"RM1 raw SWR-meter frame parsed");
        Check(rmData.swrMeterDots == 15 && !rmData.swrValid,
              @"RM1 retains 15 raw dots and does not fabricate an SWR ratio");

        // Voltage uses the documented LAB599 VL; command, not an RM meter selector.
        BOOL vlTenthsOK = [TX500TelemetryEngine parseVLReply:@"VL0121;" intoData:rmData];
        Check(vlTenthsOK, @"VL voltage frame with tenths scaling parsed");
        Check(rmData.voltageValid && fabs(rmData.voltage - 12.1) < 0.01, @"VL0121 maps accurately to 12.1V");

        TXTelemetryData *vlHundredthsData = [TXTelemetryData new];
        BOOL vlHundredthsOK = [TX500TelemetryEngine parseVLReply:@"\r\nVL1210;\r\n" intoData:vlHundredthsData];
        Check(vlHundredthsOK, @"VL voltage frame with hundredths scaling and line noise parsed");
        Check(vlHundredthsData.voltageValid && fabs(vlHundredthsData.voltage - 12.1) < 0.01,
              @"VL1210 maps accurately to 12.1V");

        TXTelemetryData *physicalReplyData = [TXTelemetryData new];
        Check([TX500TelemetryEngine parseVLReply:@"VL12.1 ;" intoData:physicalReplyData],
              @"Exact physical TX-500 reply format is parsed");
        Check(fabs(physicalReplyData.voltage - 12.1) < 0.01, @"Physical TX-500 reply maps to 12.1V");

        TXTelemetryData *invalidVoltage = [TXTelemetryData new];
        Check(![TX500TelemetryEngine parseVLReply:@"?;" intoData:invalidVoltage], @"CAT error is not accepted as voltage");
        Check(![TX500TelemetryEngine parseRMReply:@"RM50138;" intoData:invalidVoltage], @"Undocumented RM5 selector is rejected");
        Check(!invalidVoltage.voltageValid, @"Invalid reply cannot mark voltage as verified");

        // 4. Parser: SM; S-Meter frame
        BOOL smOk = [TX500TelemetryEngine parseSMReply:@"SM00018;" intoData:rmData];
        Check(smOk, @"SM S-Meter frame parsed");
        Check(rmData.sMeterValid && rmData.sMeterDots == 18, @"S-meter 18 raw dots parsed accurately");
        Check(![TX500TelemetryEngine parseSMReply:@"SM00031;" intoData:rmData], @"Out-of-range S-meter frame rejected");

        // 5. Demo / Simulation Generator Check
        TX500TelemetryEngine *engine = [TX500TelemetryEngine new];
        TXTelemetryData *demoData = [TXTelemetryData new];
        for (int i = 0; i < 150; i++) {
            [engine stepDemo:demoData];
            [demoData evaluateAlarms];
            Check(demoData.voltageValid, @"Demo voltage is explicitly marked valid");
            Check(demoData.frequencyValid && demoData.modeValid && demoData.txStateValid && demoData.sMeterValid,
                  @"Demo radio state is explicitly marked valid");
            Check(demoData.currentValid && demoData.rfPowerValid && demoData.temperatureValid,
                  @"Demo-only synthetic measurements are explicitly marked valid");
            Check(demoData.voltage >= 9.0 && demoData.voltage <= 16.0, @"Demo voltage in range");
            Check(demoData.currentAmps >= 0.05 && demoData.currentAmps <= 4.0, @"Demo current in range");
            Check(demoData.rfPowerWatts >= 0.0 && demoData.rfPowerWatts <= 12.0, @"Demo RF power in range");
            Check(demoData.swr >= 1.0 && demoData.swr <= 5.0, @"Demo SWR in range");
            Check(demoData.temperatureCelsius >= 10.0 && demoData.temperatureCelsius <= 70.0, @"Demo temp in range");
        }

        // 6. Rolling Averages Check
        Check(demoData.voltageAverages != nil, @"Voltage averages object exists");
        Check(demoData.voltageAverages.hasData == YES, @"Voltage averages has pre-seeded data");
        Check(demoData.voltageAverages.avg5m >= 10.0 && demoData.voltageAverages.avg5m <= 15.0, @"5m voltage average in valid range");
        Check(demoData.voltageAverages.avg15m >= 10.0 && demoData.voltageAverages.avg15m <= 15.0, @"15m voltage average in valid range");
        Check(demoData.voltageAverages.avg30m >= 10.0 && demoData.voltageAverages.avg30m <= 15.0, @"30m voltage average in valid range");
        Check(demoData.voltageAverages.avg60m >= 10.0 && demoData.voltageAverages.avg60m <= 15.0, @"60m voltage average in valid range");

        Check(demoData.rfPowerAverages != nil && demoData.rfPowerAverages.hasData, @"Power averages populated");
        Check(demoData.rfPowerAverages.avg5m >= 0.0 && demoData.rfPowerAverages.avg5m <= 12.0, @"5m power average in valid range");
        Check(demoData.swrAverages != nil && demoData.swrAverages.hasData, @"SWR averages populated");
        Check(demoData.swrAverages.avg5m >= 1.0 && demoData.swrAverages.avg5m <= 4.0, @"5m SWR average in valid range");
        Check(demoData.temperatureAverages != nil && demoData.temperatureAverages.hasData, @"Temp averages populated");
        Check(demoData.temperatureAverages.avg5m >= 20.0 && demoData.temperatureAverages.avg5m <= 65.0, @"5m temp average in valid range");

        printf("PASS: Telemetry validity, CAT parser, alarm, demo, and rolling-average checks passed.\n");
    }
    return 0;
}
