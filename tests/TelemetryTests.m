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
        Check(d.voltage >= 13.0 && d.voltage <= 14.0, @"Default voltage is nominal 13.8V");
        Check(d.currentAmps < 0.20, @"Default RX current is ~110 mA");
        Check(d.rfPowerWatts == 0.0, @"Default RF power is 0W");
        Check(d.swr == 1.0, @"Default SWR is 1.0");
        Check(!d.overvoltageAlert && !d.highSWRAlert && !d.overtempAlert, @"Default has no safety alarms");

        // Overvoltage test (>15.0V)
        d.voltage = 15.5;
        [d evaluateAlarms];
        Check(d.overvoltageAlert == YES, @"Overvoltage guard triggers at >15.0V");

        // Low voltage test (<9.5V)
        d.voltage = 9.2;
        [d evaluateAlarms];
        Check(d.lowVoltageAlert == YES, @"Low battery guard triggers at <9.5V");

        // High SWR test (>=3.0)
        d.swr = 3.5;
        [d evaluateAlarms];
        Check(d.highSWRAlert == YES, @"High SWR guard triggers at >=3.0");

        // PA Overheat test (>60.0°C)
        d.temperatureCelsius = 65.0;
        [d evaluateAlarms];
        Check(d.overtempAlert == YES, @"PA thermal guard triggers at >60°C");

        // Power Source classification tests (BP-500/550 vs External DC)
        d.voltage = 11.8;
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

        NSString *ifDig = @"IF00007074000     +0000000000600000 ;";
        [TX500TelemetryEngine parseIFReply:ifDig intoData:ifData];
        Check(ifData.frequencyHz == 7074000, @"Frequency parsed accurately (7.074 MHz)");
        Check(ifData.isTransmitting == NO, @"RX state parsed from IF frame");
        Check([ifData.operatingMode isEqualToString:@"DIG"], @"DIG mode parsed from IF frame");

        // 3. Parser: RM; meter frames
        TXTelemetryData *rmData = [TXTelemetryData new];
        // Power (type 0, 30 dots = 10W)
        BOOL rm0Ok = [TX500TelemetryEngine parseRMReply:@"RM00030;" intoData:rmData];
        Check(rm0Ok, @"RM0 power frame parsed");
        Check(fabs(rmData.rfPowerWatts - 10.0) < 0.1, @"10W maximum RF power mapped accurately");

        // SWR (type 1, 15 dots = 3.0 SWR)
        BOOL rm1Ok = [TX500TelemetryEngine parseRMReply:@"RM10015;" intoData:rmData];
        Check(rm1Ok, @"RM1 SWR frame parsed");
        Check(fabs(rmData.swr - 3.0) < 0.1, @"SWR 3.0 mapped accurately from 15 dots");

        // Voltage (type 5, 138 tenths = 13.8V)
        BOOL rm5Ok = [TX500TelemetryEngine parseRMReply:@"RM50138;" intoData:rmData];
        Check(rm5Ok, @"RM5 Voltage frame parsed");
        Check(fabs(rmData.voltage - 13.8) < 0.1, @"Voltage 13.8V mapped accurately");

        // Temperature (type 6, 42°C)
        BOOL rm6Ok = [TX500TelemetryEngine parseRMReply:@"RM60042;" intoData:rmData];
        Check(rm6Ok, @"RM6 Temperature frame parsed");
        Check(fabs(rmData.temperatureCelsius - 42.0) < 0.1, @"PA Temp 42°C mapped accurately");

        // 4. Parser: SM; S-Meter frame
        BOOL smOk = [TX500TelemetryEngine parseSMReply:@"SM00018;" intoData:rmData];
        Check(smOk, @"SM S-Meter frame parsed");
        Check(rmData.sMeterDots == 18, @"S-meter 18 dots parsed accurately");

        // 5. Demo / Simulation Generator Check
        TX500TelemetryEngine *engine = [TX500TelemetryEngine new];
        TXTelemetryData *demoData = [TXTelemetryData new];
        for (int i = 0; i < 150; i++) {
            [engine stepDemo:demoData];
            [demoData evaluateAlarms];
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

        printf("PASS: All 20 Telemetry, CAT parser & Rolling Average checks passed successfully.\n");
    }
    return 0;
}
