#import <Cocoa/Cocoa.h>
#import "../Headers/Lab599FeedbackController.h"

static void Check(BOOL ok, NSString *label) {
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", label.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        printf("Running Feedback and GitHub Issues integration tests...\n");

        Lab599FeedbackController *ctrl = [Lab599FeedbackController new];
        Check(ctrl != nil, @"Feedback controller instantiates");
        Check(ctrl.view != nil, @"Feedback controller view exists");
        Check(ctrl.categoryPicker != nil, @"Category picker exists");
        Check(ctrl.priorityPicker != nil, @"Priority picker exists");
        Check(ctrl.callsignField != nil, @"Callsign field exists");
        Check(ctrl.contactField != nil, @"Contact field exists");
        Check(ctrl.titleField != nil, @"Title field exists");
        Check(ctrl.detailsView != nil, @"Details text view exists");
        Check(ctrl.diagnosticsCheckbox != nil, @"Diagnostics checkbox exists");
        Check(ctrl.diagnosticsView != nil, @"Diagnostics view exists");
        printf("PASS: Controller and all subviews instantiated successfully.\n");

        // 1. Diagnostics generation
        ctrl.selectedPortProvider = ^NSString * { return @"/dev/cu.usbserial-TEST1234"; };
        [ctrl refreshDiagnostics];
        Check([ctrl.diagnosticsView.string containsString:@"Lab599 Utility"], @"Diagnostics contains app name");
        Check([ctrl.diagnosticsView.string containsString:@"/dev/cu.usbserial-TEST1234"], @"Diagnostics contains active port");
        printf("PASS: Diagnostics snapshot generation verified.\n");

        // 2. User defaults and field persistence
        ctrl.callsignField.stringValue = @"EP2AES";
        ctrl.contactField.stringValue = @"ep2aes@asis.sh";
        ctrl.categoryPicker.selectedSegment = 1; // Bug
        ctrl.priorityPicker.selectedSegment = 2; // Urgent
        ctrl.titleField.stringValue = @"Serial buffer overflow on rapid CAT poll";
        ctrl.detailsView.string = @"When polling FA; rapidly at 50Hz, serial buffer overflows.";

        NSString *md = [ctrl generateIssueMarkdown];
        Check([md containsString:@"### Summary\nSerial buffer overflow on rapid CAT poll"], @"Markdown contains title summary");
        Check([md containsString:@"- **Category**: Bug"], @"Markdown contains Bug category");
        Check([md containsString:@"- **Priority**: Urgent"], @"Markdown contains Urgent priority");
        Check([md containsString:@"- **Callsign**: EP2AES"], @"Markdown contains Callsign");
        Check([md containsString:@"- **Contact**: ep2aes@asis.sh"], @"Markdown contains Contact info");
        Check([md containsString:@"When polling FA; rapidly"], @"Markdown contains detailed description");
        Check([md containsString:@"### System & Radio Diagnostics"], @"Markdown contains diagnostics snapshot");
        Check([md containsString:@"/dev/cu.usbserial-TEST1234"], @"Markdown contains active serial port");
        printf("PASS: Markdown report generation verified.\n");

        // 3. GitHub Issue URL generation
        NSURL *issueURL = [ctrl generateGitHubIssueURL];
        Check(issueURL != nil, @"GitHub Issue URL generated");
        Check([issueURL.scheme isEqualToString:@"https"], @"URL scheme is https");
        Check([issueURL.host isEqualToString:@"github.com"], @"URL host is github.com");
        Check([issueURL.path isEqualToString:@"/fact0real/Lab599-Utility/issues/new"], @"URL path is /fact0real/Lab599-Utility/issues/new");
        Check([issueURL.query containsString:@"title="], @"URL query contains title parameter");
        Check([issueURL.query containsString:@"labels="], @"URL query contains labels parameter");
        Check([issueURL.query containsString:@"bug"], @"URL query contains bug label for category Bug");
        printf("PASS: GitHub new issue URL generation verified (%lu chars).\n", (unsigned long)issueURL.absoluteString.length);

        // 4. Feature Category test
        ctrl.categoryPicker.selectedSegment = 0; // Feature
        NSURL *featURL = [ctrl generateGitHubIssueURL];
        Check([featURL.query containsString:@"enhancement"], @"Feature maps to enhancement label");
        printf("PASS: Category to GitHub label mapping verified.\n");

        // 5. Diagnostics Toggle test
        ctrl.diagnosticsCheckbox.state = NSControlStateValueOff;
        NSString *mdNoDiag = [ctrl generateIssueMarkdown];
        Check(![mdNoDiag containsString:@"### System & Radio Diagnostics"], @"Diagnostics omitted when checkbox unchecked");
        printf("PASS: Diagnostics checkbox toggle verified.\n");

        // 6. Form Clearing test
        [ctrl clearForm];
        Check([ctrl.titleField.stringValue isEqualToString:@""], @"Title cleared");
        Check([ctrl.detailsView.string isEqualToString:@""], @"Details cleared");
        Check(ctrl.priorityPicker.selectedSegment == 0, @"Priority reset to Normal");
        printf("PASS: Form reset verified.\n");

        printf("All Feedback tests passed successfully.\n");
    }
    return 0;
}
