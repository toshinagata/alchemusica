//
//  QuantizePanelController.h
//  Alchemusica
//
//  Created by Toshi Nagata on 12/01/14.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

extern NSString *QuantizeNoteKey, *QuantizeStrengthKey, *QuantizeSwingKey;

@interface QuantizePanelController : NSWindowController {
	float timebase;
	IBOutlet NSPopUpButton *unitNotePopUp;
	IBOutlet NSTextField *unitText;
	IBOutlet NSSlider *strengthSlider;
	IBOutlet NSTextField *strengthText;
	IBOutlet NSSlider *swingSlider;
	IBOutlet NSTextField *swingText;
}
- (void)setTimebase:(float)timebase;
- (IBAction)unitChanged:(id)sender;
- (IBAction)strengthChanged:(id)sender;
- (IBAction)swingChanged:(id)sender;
- (IBAction)okPressed:(id)sender;
- (IBAction)cancelPressed:(id)sender;
@end
