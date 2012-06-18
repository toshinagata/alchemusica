/* GraphicWindowController.h */
/*
    Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>
#import "MDHeaders.h"

#define kGraphicWindowControllerMaxNumberOfClientViews  8

@class GraphicClientView;
@class GraphicRulerView;
@class GraphicSplitterView;
@class PlayingViewController;

typedef struct ClientRecord {
	GraphicClientView *client;
	GraphicRulerView  *ruler;
	GraphicSplitterView *splitter;
} ClientRecord;

typedef struct TrackInfo {
	int trackNum;
	char focusFlag;
} TrackInfo;

//  Associated operations for each track
enum {
	kGraphicShow = 1,  //  show the events
	kGraphicEdit = 2,  //  allow editing existing events
	kGraphicDraw = 4   //  allow inserting new events (with pencil tools)
};

//  Graphic Tool (returned by graphicTool)
enum {
	kGraphicRectangleSelectTool = 1,
	kGraphicIbeamSelectTool,
	kGraphicPencilTool
};

//  Line shape (returned by graphicLineShape)
enum {
	kGraphicLinearShape = 1,
	kGraphicParabolaShape,
	kGraphicArcShape,
	kGraphicSigmoidShape,
	kGraphicRandomShape
};

/*
//  Selection mode (returned by graphicSelectionMode)
enum {
    kGraphicRectangleSelectionMode = 0,
	kGraphicIbeamSelectionMode,
    kGraphicMarqueeSelectionMode
};
*/

//  Editing mode for strip chart (returned by graphicEditingMode)
enum {
	kGraphicSetMode = 1,
	kGraphicAddMode,
	kGraphicScaleMode,
	kGraphicLimitMaxMode,
	kGraphicLimitMinMode
};

enum {
	kRecButtonTag = 0,
	kStopButtonTag,
	kForwardButtonTag,
	kRewindButtonTag,
	kPauseButtonTag,
	kPlayButtonTag
};

@interface GraphicWindowController : NSWindowController
{
	IBOutlet NSView *myMainView;        //  Main graphic view (containing piano roll, etc.)
	IBOutlet NSTableView *myTableView;  //  Track table
	IBOutlet NSView *myFloatingView;    //  View to draw playing cursor etc.
	IBOutlet NSView *myToolbarView;     //  The view containing tools for graphic editing
	IBOutlet NSScroller *myScroller;    //  The common scroller for all graphic client views
	
	IBOutlet NSView *myPlayerView;      //  The view containing player controls
	IBOutlet PlayingViewController *playingViewController;  //  The playing view controller
	
	//  0: TimeChartView, 1: PianoRollView, 2 and after: StripChartView
	int myClientViewsCount;
	ClientRecord records[kGraphicWindowControllerMaxNumberOfClientViews];
	
    MDCalibrator *calib;	//  calibrator for tick conversion
    
	/*  The visible and editable track numbers are cached in this array  */
	int *sortedTrackNumbers; // If NULL, then needs update
	int visibleTrackCount;   // If negative, then sortedTrackNumbers needs update

	float beginTick;        //  The tick of the left origin
	float pixelsPerQuarter;    //  Pixels per a quarter note
	float quantize;         //  Mouse position quantize (unit = quarter note; 0: no quantize)

	//  Note on/off are cached here too
	NSArray *noteCache;
	float noteCacheBeginBeat, noteCacheEndBeat;

	//  The position of the time indicator during playing
	float timeIndicatorPos;		//  In tick
	NSRect timeIndicatorRect;	//  In window coordinates
    
    //  Tracking rect
    NSTrackingRectTag trackingRectTag;
	
	//  Graphic Tool/LineShape/Mode
	int graphicTool;
	int graphicLineShape;
	int graphicEditingMode;
//	int graphicSelectionMode;
	
	//  Client view that received the last mouse event
	int lastMouseClientViewIndex;
	
	//  Zoom/unzoom buffer and current position
	NSMutableArray *zoomUndoBuffer;
	int zoomUndoIndex;
	
	//  Selected tracks when the selection changed last
	NSIndexSet *lastSelectedTracks;
}

//+ (NSCursor *)horizontalMoveCursor;
//+ (NSCursor *)verticalMoveCursor;
//+ (NSCursor *)stretchCursor;
//+ (NSCursor *)moveAroundCursor;

- (float)rulerWidth;

- (id)init;

//  NSWindowControllerAdditions overrides
+ (BOOL)canContainMultipleTracks;

- (void)setFocusFlag: (BOOL) flag onTrack: (int)trackNum extending: (BOOL)extendFlag;
- (BOOL)isFocusTrack: (int)trackNum;
- (BOOL)isTrackSelected: (long)trackNo;
- (void)setIsTrackSelected: (long)trackNo flag: (BOOL)flag;

- (long)trackCount;
- (long)visibleTrackCount;
- (int)sortedTrackNumberAtIndex: (int)index;  // For clientViews; focus track comes first

- (float)pixelsPerQuarter;
- (void)setPixelsPerQuarter: (float)newPixelsPerQuarter;
- (float)pixelsPerTick;
- (MDTickType)quantizedTickFromPixel: (float)pixel;
- (float)quantizedPixelFromPixel: (float)pixel;
- (float)pixelQuantum;

- (float)scrollPositionOfClientViews;
- (void)scrollClientViewsToPosition: (float)pos;
- (void)scrollClientViewsToTick: (MDTickType)tick;

- (void)verticalLinesFromTick: (MDTickType)fromTick timeSignature: (MDEvent **)timeSignature nextTimeSignature: (MDEvent **)nextTimeSignature lineIntervalInPixels: (float *)lineIntervalInPixels mediumCount: (int *)mediumCount majorCount: (int *)majorCount;

- (MDTickType)sequenceDuration;
- (float)sequenceDurationInQuarter;
- (void)setInfoText: (NSString *)string;

- (void)setStripChartAtIndex: (int)index kind: (int)kind code: (int)code;
- (IBAction)kindPopUpPressed: (id)sender;
- (IBAction)codeMenuItemSelected: (id)sender;

- (IBAction)expandHorizontally: (id)sender;
- (IBAction)shrinkHorizontally: (id)sender;

- (IBAction)toolButton: (id)sender;
- (IBAction)shapeSelected: (id)sender;
- (IBAction)modeSelected: (id)sender;

- (IBAction)scrollerMoved: (id)sender;

- (IBAction)quantizeSelected: (id)sender;

- (void)scrollClientViewsToPosition: (float)pos;
- (void)scrollClientViewsToTick: (MDTickType)tick;
- (void)zoomClientViewsWithPixelsPerQuarter:(float)ppq startingPos:(float)pos;
- (void)unzoomClientViews;
- (void)rezoomClientViews;

- (void)setNeedsReloadClientViews;
- (void)reloadClientViews;
- (void)reflectClientViews;
- (float)clientViewWidth;

- (void)mouseEvent:(NSEvent *)theEvent receivedByClientView:(GraphicClientView *)cView;
- (GraphicClientView *)lastMouseClientView;

- (void)convertTick: (MDTickType)aTick toMeasure: (long *)measure beat: (long *)beat andTick: (long *)tick;

//  Action method for GraphicSplitterView
- (void)splitterView: (GraphicSplitterView *)theView isDraggedTo: (float)y confirm: (BOOL)confirm;

//  Customized autoresizing for client views
- (void)resizeClientViewsWithOldMainViewSize: (NSSize)oldSize;

//  Modify data according to mouse events in the GraphicClientViews
- (void)dragNotesByTick: (MDTickType)deltaTick andNote: (int)deltaNote sender: (GraphicClientView *)sender optionFlag: (BOOL)optionFlag;
- (void)dragDurationByTick: (MDTickType)deltaTick sender: (GraphicClientView *)sender;
- (void)dragEventsOfKind: (int)kind andCode: (int)code byTick: (MDTickType)deltaTick andValue: (float)deltaValue sender: (GraphicClientView *)sender optionFlag: (BOOL)optionFlag;

- (NSColor *)colorForTrack: (int)track enabled: (BOOL)flag;

//  Accessor for current tool/lineshape/mode
- (int)graphicTool;
- (int)graphicLineShape;
- (int)graphicEditingMode;
//- (int)graphicSelectionMode;
- (GraphicClientView *)clientViewAtIndex: (int)index;

//  Action methods for track table
- (IBAction)openEventListWindow: (id)sender;
- (IBAction)createNewTrack: (id)sender;
- (IBAction)deleteSelectedTracks:(id)sender;
- (IBAction)remapDevice: (id)sender;

//  Action methods for graphic views
- (IBAction)changeControlNumber:(id)sender;
- (IBAction)shiftSelectedEvents:(id)sender;

//  Accessor for the subview controller
- (id)playingViewController;

@end
