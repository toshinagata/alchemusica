//
//  QuantizePanelController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 12/01/14.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "QuantizePanelController.h"
#import "MyAppController.h"

NSString
*QuantizeNoteKey = @"quantize.note",  /*  Expressed internally as timebase = 480  */
*QuantizeStrengthKey = @"quantize.strength",
*QuantizeSwingKey = @"quantize.swing";

@implementation QuantizePanelController

- (id)init
{
	self = [super initWithWindowNibName:@"QuantizePanel"];
	if (self) {
		timebase = 480.0f;
	}
	return self;
}

- (void)updateDisplay
{
	id obj;
	int ival;
	float fval;
	obj = MyAppCallback_getObjectGlobalSettings(QuantizeNoteKey);
	if (obj == nil) {
		obj = [NSNumber numberWithFloat:480.0f];
		MyAppCallback_setObjectGlobalSettings(QuantizeNoteKey, obj);
	}
	fval = [obj floatValue];
	for (ival = 0; ival < 18; ival++) {
		if ([[unitNotePopUp itemAtIndex:ival] tag] == fval) {
			[unitNotePopUp selectItemAtIndex:ival];
			break;
		}
	}
	if (ival == 18)
		[unitNotePopUp selectItemAtIndex:-1];
	ival = (int)floor(fval * timebase / 480.0f + 0.5f);
	[unitText setIntValue:ival];

	obj = MyAppCallback_getObjectGlobalSettings(QuantizeStrengthKey);
	if (obj == nil) {
		obj = [NSNumber numberWithFloat:0.5f];
		MyAppCallback_setObjectGlobalSettings(QuantizeStrengthKey, obj);
	}
	fval = [obj floatValue];
	[strengthSlider setFloatValue:fval];
	[strengthText setFloatValue:fval];
	
	obj = MyAppCallback_getObjectGlobalSettings(QuantizeSwingKey);
	if (obj == nil) {
		obj = [NSNumber numberWithFloat:0.0f];
		MyAppCallback_setObjectGlobalSettings(QuantizeSwingKey, obj);
	}
	fval = [obj floatValue];
	[swingSlider setFloatValue:fval];
	[swingText setFloatValue:fval];
}

- (void)windowDidLoad
{
	NSMenu *menu;
	NSMenuItem *menuItem;
	int i, j;
	[super windowDidLoad];
	menu = [unitNotePopUp menu];
	for (i = 0; i < 3; i++) {
		static NSString *fmt[] = {@"note%d.png", @"note%dd.png", @"note%d_3.png"};
		static int notelen[] = {1920, 2880, 1280};
		for (j = 1; j <= 32; j *= 2) {
			menuItem = [[[NSMenuItem allocWithZone: [self zone]] initWithTitle: @"" action: nil keyEquivalent: @""] autorelease];
			[menuItem setImage: [NSImage imageNamed: [NSString stringWithFormat: fmt[i], j]]];
			[menuItem setTag:notelen[i] / j];  /*  Note length for timebase = 480  */
			[menu addItem: menuItem];
		}
	}
	[self updateDisplay];
}

- (void)setTimebase:(float)newTimebase
{
	timebase = newTimebase;
	[self updateDisplay];
}

- (IBAction)unitChanged:(id)sender
{
	float fval;
	if (sender == unitNotePopUp)
		fval = [[sender selectedItem] tag];
	else if (sender == unitText)
		fval = [sender floatValue] * 480.0f / timebase;
	else return;
	MyAppCallback_setObjectGlobalSettings(QuantizeNoteKey, [NSNumber numberWithFloat:fval]);
	[self updateDisplay];
}

- (IBAction)strengthChanged:(id)sender
{
	float fval;
	fval = [sender floatValue];
	if (fval < 0.0f)
		fval = 0.0f;
	if (fval > 1.0f)
		fval = 1.0f;
	MyAppCallback_setObjectGlobalSettings(QuantizeStrengthKey, [NSNumber numberWithFloat:fval]);
	[self updateDisplay];
}

- (IBAction)swingChanged:(id)sender
{
	float fval;
	fval = [sender floatValue];
	if (fval < 0.0f)
		fval = 0.0f;
	if (fval > 1.0f)
		fval = 1.0f;
	MyAppCallback_setObjectGlobalSettings(QuantizeSwingKey, [NSNumber numberWithFloat:fval]);
	[self updateDisplay];
}

- (IBAction)okPressed:(id)sender
{
	[NSApp stopModal];
}

- (IBAction)cancelPressed:(id)sender
{
	[NSApp abortModal];
}

@end
