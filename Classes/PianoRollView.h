/* PianoRollView.h */
/*
    Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>
#import "GraphicClientView.h"
#import "MDHeaders.h"

@interface PianoRollView : GraphicClientView
{
    /*  Cache the positions of notes whose note-offs are after cacheTick  */
    MDTickType cacheTick;
    NSMutableArray *cacheArray; /*  An array of IntGroupObject; the number of objects is the number of visible tracks, plus 1 for temporary recording track if present  */
	int32_t mouseDownTrack;  /*  mouseDownTrack/mouseDownPos remembers the position of the note on which the mouse down event was detected  */
	int32_t mouseDownPos;
    int draggingMode;
    NSPoint draggingStartPoint;
    NSPoint draggingPoint;
    NSImage *draggingImage;
    NSRect limitRect;
	NSRect selectionRect;
	BOOL pencilOn;  /* True if drawing with a pencil */
    
	/*  Note on during dragging etc.  */
	short playingNote;
	short playingVelocity;
	int32_t playingTrack;

    /*  Rubbing: play the note while dragging with option key down  */
    BOOL rubbing;
    NSMutableArray *rubbingArray;  /*  An array of IntGroupObject; the number of objects is the number of editable tracks  */
    MDTickType rubbingTick;

}
- (void)mouseExited: (NSEvent *)theEvent;  //  Should stop rubbing

@end
