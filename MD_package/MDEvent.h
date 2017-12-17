/*
 *  MDEvent.h
 *
 *  Created by Toshi Nagata on Sun Jun 17 2001.

   Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#ifndef __MDEvent__
#define __MDEvent__

#ifndef __MDCommon__
#include "MDCommon.h"
#endif

/*  MD イベントの種類を表す定数  */
typedef unsigned char MDEventKind;
enum {
	kMDEventNull        = 0,
	kMDEventMeta,					/*  code = meta code, data1/data2 = data  */
	kMDEventTempo,					/*  tempo = tempo (number of quarters per minutes)  */
	kMDEventTimeSignature,			/*  metadata[0] = numerator,
										metadata[1] = denominator (negative power of 2 as in SMF),
										metadata[2] = length of one metronome-click
											(multiples of 1/24 of quarter note)
										metadata[3] = the number of 32-nd notes per
                                            24 MIDI clocks (usually 8)  */
	kMDEventKey,					/*  metadata[0] = key (-7 to 7), metadata[1] = major or minor */
	kMDEventSMPTE,					/*  SMPTE record (hour, min, sec, frame, subframe) */
	kMDEventPortNumber,				/*  data1 = port number  */
	kMDEventMetaText,				/*  code = meta code, message = message (text) */
	kMDEventMetaMessage,			/*  code = meta code, message = message  */
	kMDEventProgram,				/*  data1 = program, data2 = bank select */
	kMDEventNote,					/*  code = key code,
										data1 = (on-velocity << 8) + off-velocity,
									    duration/m_duration = duration  */
	kMDEventInternalNoteOff,		/*  used only for temporary use; code = key code, vel[1] = off-velocity, ldata = track number  */
	kMDEventInternalNoteOn,         /*  used only for temporary use; code = key code, vel[0] = on-velocity, duration (optional) = expected duration  */
	kMDEventInternalDuration,		/*  used only for temporary use; duration = expected duration of the immediately following note-on  */
	kMDEventControl,				/*  code = control code, data1 = control data  */
	kMDEventPitchBend,				/*  data1 = pitch bend value */
	kMDEventChanPres,				/*  data1 = channel pressure value */
	kMDEventKeyPres,				/*  code = key code, data1 = key pressure value */
	kMDEventSysex,					/*  message = sysex message (beginning from 'F0') */
	kMDEventSysexCont,				/*  message = sysex message (not beginning from 'F0') */
	kMDEventData,					/*  code = data identifier, dataptr = a pointer to
									   a memory block allocated by malloc()  */
	kMDEventObject,					/*  code = data identifier, objptr = a pointer to
									   a object that can be released by MDReleaseObject(objptr) call */
	kMDEventSpecial,                /*  code = special code  */
	kMDEventStop
};

/*  SMF イベントの種類  */
enum {
	kMDEventSMFNoteOff			= 0x80,
	kMDEventSMFNoteOn			= 0x90,
	kMDEventSMFKeyPressure		= 0xa0,
	kMDEventSMFControl			= 0xb0,
	kMDEventSMFProgram			= 0xc0,
	kMDEventSMFChannelPressure	= 0xd0,
	kMDEventSMFPitchBend		= 0xe0,
	kMDEventSMFSysex			= 0xf0,
	kMDEventSMFSysexF7			= 0xf7,
	kMDEventSMFMeta				= 0xff
};

/*  メタイベントの種類をあらわす定数  */
typedef unsigned char MDMetaKind;
enum {
	kMDMetaSequenceNumber = 0,
	kMDMetaText = 1,
	kMDMetaCopyright = 2,
	kMDMetaSequenceName = 3,
	kMDMetaInstrumentName = 4,
	kMDMetaLyric = 5,
	kMDMetaMarker = 6,
	kMDMetaCuePoint = 7,
	kMDMetaProgramName = 8,			/*  New in RP-016  */
	kMDMetaDeviceName = 9,			/*  New in RP-016  */
	kMDMetaChannelPrefix = 0x20,
	kMDMetaPortNumber = 0x21,
	kMDMetaEndOfTrack = 0x2f,
	kMDMetaTempo = 0x51,
	kMDMetaSMPTE = 0x54,
	kMDMetaTimeSignature = 0x58,
	kMDMetaKey = 0x59,
	kMDMetaSequencerSpecific = 0x7f,

	/*  Internally used to keep track of durations of overlapping notes  */
	/*  It contains a BER-compressed integer and represents the duration of the preceding
		note-on event.  */
	kMDMetaDuration = 0x7e
};

/*  Type of special events  */
enum {
	kMDSpecialEndOfSequence = 0,
	kMDSpecialStopPlaying
};

/*  tick および絶対時間を扱う型。絶対時間の単位はマイクロ秒。  */
typedef int32_t		MDTickType;
typedef int64_t	MDTimeType;

#define kMDMaxTick		((MDTickType)0x7ffffff0)
#define kMDNegativeTick	((MDTickType)-1)
#define kMDMaxTime		((MDTimeType)10000000000000.0)
#define kMDNegativeTime ((MDTimeType)-1)

#define kMDMaxTempo		100000.0f	/*  Somewhat arbitrary (anything less than 60000000)  */
#define kMDMinTempo		3.60f		/*  Quite strict  */

#define kMDMaxData      80000000.0f
#define kMDMinData      -80000000.0f

#define kMDMaxPosition  0x7ffffff0
#define kMDNegativePosition -1

/*  メッセージデータ（Sysex やテキスト系メタイベント）を格納する構造体
	本体は MDEvent.c で定義される  */
typedef struct MDMessage			MDMessage;

/*  SMPTE データを格納するためのビットフィールド構造体  */
typedef struct MDSMPTERecord {
	unsigned int	reserved: 1;
	unsigned int	hour: 6;		/*  including SMPTE type (upper 2 bits) */
	unsigned int	min: 6;
	unsigned int	sec: 6;
	unsigned int	frame: 5;
	unsigned int	subframe: 8;
} MDSMPTERecord;

/*  MIDI イベントそのものを格納する構造体。opaque ではなく、MDEvent 自体も使ってよい。
    ただし、フィールドに直接アクセスすることは好ましくなく、アクセスマクロを使うこと。 */
typedef struct MDEvent				MDEvent;
struct MDEvent {
	MDEventKind		kind;		/*  The kind of this event record  */
	unsigned char	code;		/*  key code or meta-event code  */
	short			channel;	/*  channel number; 0-15: MIDI channel 0-15, 16: sysex, 17: non-MIDI  */
	MDTickType		tick;		/*  tick  */
	union {
		unsigned char vel[2];	/*  note events: note-on and note-off velocity  */
		short		data1;		/*  other events: a 16-bit value  */
	} data1;
	union {
		MDTickType		duration;	/*  for note events  */
		struct {
			short		data2;		/*  for other MIDI events  */
			short		data3;
		} d;
		int32_t			ldata;		/*  for internal note-off event  */
		unsigned char	metadata[4];	/*  meta events  */
		MDSMPTERecord	smpte;		/*  SMPTE  */
		float			tempo;
		MDMessage *		message;
		void *			dataptr;
	} u;	
};

/*  MDEventGetDisplay などで使われるデータ構造。 */
typedef union MDEventDisplayValue {
	const char *	ccp;
	char *			cp;
	int32_t			l;
	float			f;
} MDEventDisplayValue;

/*  あるティック位置でのテンポ・拍子・調号などを覚えておくためのキャッシュ。
    キャッシュは MDSequence と連動しており、MDSequence およびそれに属するトラッ
    クに何か変更を加えた時には更新する必要がある。これは自動的には行われないので、
    変更を加えるたびに適当なタイミングで MDSequenceUpdateCache() を呼び出すこと。
	MDCache 関連の関数定義は MDSequence.h に、関数本体は MDSequence.c にある。 */
/*typedef struct MDCache		MDCache; */

/* -------------------------------------------------------------------
    MDEvent macros
   -------------------------------------------------------------------  */

/*#define MDTempoToMetronomeTempo(tp)	(60000000.0 / (tp)) */
/*#define MDMetronomeTempoToTempo(mtp) (60000000.0 / (mtp)) */
#define	MDGetKind(eventPtr)				((eventPtr)->kind)
#define	MDSetKind(eventPtr, theKind)	((eventPtr)->kind = (theKind))
#define	MDGetCode(eventPtr)				((eventPtr)->code)
#define	MDSetCode(eventPtr, theCode)	((eventPtr)->code = (theCode))
#define	MDGetChannel(eventPtr)			((eventPtr)->channel)
#define	MDSetChannel(eventPtr, theChan)	((eventPtr)->channel = (theChan))
#define	MDGetTick(eventPtr)				((eventPtr)->tick)
#define	MDSetTick(eventPtr, theTick)	((eventPtr)->tick = (theTick))
#define	MDGetData1(eventPtr)			((eventPtr)->data1.data1)
#define MDSetData1(eventPtr, theData)	((eventPtr)->data1.data1 = (theData))
#define MDGetNoteOnVelocity(eventPtr)	((eventPtr)->data1.vel[0])
#define MDSetNoteOnVelocity(eventPtr, theVel)	((eventPtr)->data1.vel[0] = (theVel))
#define MDGetNoteOffVelocity(eventPtr)	((eventPtr)->data1.vel[1])
#define MDSetNoteOffVelocity(eventPtr, theVel)	((eventPtr)->data1.vel[1] = (theVel))
#define	MDGetData2(eventPtr)			((eventPtr)->u.d.data2)
#define MDSetData2(eventPtr, theData)	((eventPtr)->u.d.data2 = (theData))
#define MDGetLData(eventPtr)			((eventPtr)->u.ldata)
#define MDSetLData(eventPtr, theData)	((eventPtr)->u.ldata = (theData))
#define MDGetDuration(eventPtr)			((eventPtr)->u.duration)
#define MDSetDuration(eventPtr, theDuration)	((eventPtr)->u.duration = (theDuration))
#define MDGetTempo(eventPtr)			((eventPtr)->u.tempo)
#define MDSetTempo(eventPtr, theTempo)	((eventPtr)->u.tempo = (theTempo))
/*#define MDGetMetronomeTempo(eventPtr)	(MDTempoToMetronomeTempo((eventPtr)->u.tempo)) */
#define	MDGetData3(eventPtr)			((eventPtr)->u.d.data3)
#define MDSetData3(eventPtr, theData)	((eventPtr)->u.d.data3 = (theData))
#define	MDGetMetaDataPtr(eventPtr)		((eventPtr)->u.metadata)
#define MDGetSMPTERecordPtr(eventPtr)	(&((eventPtr)->u.smpte))

/*  各種判定用マクロ  */
#define	MDIsChannelEvent(eventRef)	\
	(MDGetKind(eventRef) >= kMDEventProgram && MDGetKind(eventRef) <= kMDEventKeyPres)
#define	MDIsSysexEvent(eventRef)	\
	(MDGetKind(eventRef) == kMDEventSysex || MDGetKind(eventRef) == kMDEventSysexCont)
#define	MDIsMetaEvent(eventRef)		\
	(MDGetKind(eventRef) >= kMDEventMeta && MDGetKind(eventRef) <= kMDEventMetaMessage)
#define	MDIsTextMetaEvent(eventRef)	\
	(MDGetKind(eventRef) == kMDEventMetaText)
#define	MDHasEventMessage(eventRef)	\
	(MDIsSysexEvent(eventRef) || MDGetKind(eventRef) == kMDEventMetaMessage || MDGetKind(eventRef) == kMDEventMetaText)
#define	MDHasEventData(eventRef)	\
	(MDGetKind(eventRef) == kMDEventData)
#define	MDHasEventObject(eventRef)	\
	(MDGetKind(eventRef) == kMDEventObject)
#define MDIsNoteEvent(eventRef)		\
    (MDGetKind(eventRef) == kMDEventNote)
#define MDHasDuration(eventRef)		\
    (MDGetKind(eventRef) == kMDEventNote)
#define MDHasCode(eventRef)			\
	(MDIsNoteEvent(eventRef) || MDGetKind(eventRef) == kMDEventInternalNoteOff \
	|| MDGetKind(eventRef) == kMDEventControl || MDGetKind(eventRef) == kMDEventKeyPres \
	|| MDGetKind(eventRef) == kMDEventMeta || MDGetKind(eventRef) == kMDEventMetaText \
	|| MDGetKind(eventRef) == kMDEventMetaMessage)
#define MDIsTickEqual(eref1, eref2)				(MDGetTick(eref1) == MDGetTick(eref2))
#define MDIsTickGreater(eref1, eref2)			(MDGetTick(eref1) > MDGetTick(eref2))
#define MDIsTickLess(eref1, eref2)				(MDGetTick(eref1) < MDGetTick(eref2))
#define MDIsTickGreaterOrEqual(eref1, eref2)	(MDGetTick(eref1) >= MDGetTick(eref2))
#define MDIsTickLessOrEqual(eref1, eref2)		(MDGetTick(eref1) <= MDGetTick(eref2))

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------
    MDEvent functions
   -------------------------------------------------------------------  */

/*  イベントを０で初期化する。 */
void	MDEventInit(MDEvent *eventRef);

/*　イベントをクリアする。メッセージ・データ・オブジェクトを含んでいる場合はそれらを
    解放する。  */
void	MDEventClear(MDEvent *eventRef);

/*  指定された種類のデフォルトイベントを作る。 */
void	MDEventDefault(MDEvent *eventRef, int kind);

/*  イベントをコピーする。メッセージデータはポインタだけがコピーされ Retain される。 */
void	MDEventCopy(MDEvent *destRef, const MDEvent *sourceRef, int32_t count);

/*  イベントを移動させる。sourceRef は０で初期化される。 */
void	MDEventMove(MDEvent *destRef, MDEvent *sourceRef, int32_t count);

/*　メッセージの長さを得る。メッセージイベントでない場合は -1 を返す。  */
int32_t	MDGetMessageLength(const MDEvent *eventRef);

/*  srcRef から destRef にメッセージデータだけをコピーする。  */
void	MDCopyMessage(MDEvent *destRef, MDEvent *srcRef);

/*　渡されたバッファアドレスにメッセージデータをコピーする。outBuffer はメッセージを
    格納するのに十分な大きさがなければならない。
    メッセージの長さを返す。メッセージイベントでない場合は -1 を返す。 */
int32_t	MDGetMessage(const MDEvent *eventRef, unsigned char *outBuffer);

/*　メッセージデータの inOffset 目のバイト（先頭が０）から inLength バイトを outBuffer 
    にコピーする。outBuffer は最大 inLength バイトのデータを格納できる大きさがなければ
    ならない。実際にコピーしたバイト数を返す。メッセージイベントでない場合は -1 を返す。 */
int32_t	MDGetMessagePartial(const MDEvent *eventRef, unsigned char *outBuffer, int32_t inOffset, int32_t inLength);

/*	メッセージデータの長さとデータへのポインタを返す。この関数で得たポインタには
    書き込みをしてはならない。 */
const unsigned char *
		MDGetMessageConstPtr(const MDEvent *eventRef, int32_t *outLength);

/*  注意：MDGetMessagePtr, MDSetMessageLength, MDSetMessage, MDSetMessagePartial を
    呼び出した時、一見必要がないように見えても内部的にメモリ確保が行われることがある。
    これらの関数はメッセージの内容を書き換えるため、refCount を使ってコピーを保持している
    メッセージの場合は新しいコピーがその時点で作成されるからである。 */

/*	メッセージデータの長さとデータへのポインタを返す。データに書き込んでも構わないが、
	決められた長さの外側に書き込まないよう注意すること。 */
unsigned char *	MDGetMessagePtr(MDEvent *eventRef, int32_t *outLength);

/*　メッセージの長さを変更する。メッセージイベントでない場合は何もしない。inLength と
    同じ値が返されるが、メモリ不足の場合は負の値が返される。 */
int32_t	MDSetMessageLength(MDEvent *eventRef, int32_t inLength);

/*　渡されたバッファのデータをメッセージデータにコピーする。
    メッセージの長さはあらかじめセットされている値が使われる。
    メッセージの長さが返される。メモリ不足が起こった場合は負の値が返される。
    メッセージイベントでない場合は何もしない。 */
int32_t	MDSetMessage(MDEvent *eventRef, const unsigned char *inBuffer);

/*　メッセージデータの inOffset 目のバイト（先頭が０）から inLength バイトを inBuffer 
    のデータで置き換える。inOffset + inLength がメッセージの長さより長い場合は、メッ
    セージの長さちょうどで打ち切られる。
    メッセージの長さが返される。メモリ不足が起こった場合は負の値が返される。
    メッセージイベントでない場合は何もしない。 */
int32_t	MDSetMessagePartial(MDEvent *eventRef, const unsigned char *inBuffer, int32_t inOffset, int32_t inLength);

/*  イベントデータと表示データの相互変換。  */

/*  ノートナンバーをノート名に変換する。 */
void	MDEventNoteNumberToNoteName(unsigned char inNumber, char *outName);

/*  ノート名をノートナンバーに変換する。 */
int		MDEventNoteNameToNoteNumber(const char *p);

/*  五線（加線）の番号をノートナンバーに変換する。五線番号は、中央のＣが０で、上が正、下が負の整数。 */
int		MDEventStaffIndexToNoteNumber(int staff);

/*  イベントを表示用文字列に変換する。length は buf[] に格納できる最大の文字数（最後のヌル文字を含む） */
int32_t	MDEventToKindString(const MDEvent *eref, char *buf, int32_t length);
int32_t	MDEventToDataString(const MDEvent *eref, char *buf, int32_t length);
int32_t	MDEventToGTString(const MDEvent *eref, char *buf, int32_t length);

/*  表示用文字列からイベントデータを得る。code はイベントのどの部分に対応するかをあらわす定数。  */
typedef short MDEventFieldCode;
enum {
	kMDEventFieldNone = 0,
	kMDEventFieldKindAndCode,		/* Code は無意味な場合もある  */
	kMDEventFieldTick,
	kMDEventFieldCode,
	kMDEventFieldData,				/* data1 */
	kMDEventFieldVelocities,		/* ucValue[0] が on-velocity, ucValue[1] が off-velocity  */
	kMDEventFieldSMPTE,
	kMDEventFieldMetaData,
	kMDEventFieldTempo,
	kMDEventFieldBinaryData,		/* Meta event/sysex data (including text)  */
	kMDEventFieldPointer,
	kMDEventFieldInvalid
};

/*  MDEventFieldData と少なくとも同じサイズの整数型  */
typedef intptr_t MDEventFieldDataWhole;
typedef union MDEventFieldData {
	MDEventFieldDataWhole whole;			
	int32_t			intValue;		/*  code, data1  */
	float			floatValue;		/*  tempo  */
	MDSMPTERecord	smpte;			/*  SMPTE  */
	MDTickType      tickValue;      /*  tick  */
	unsigned char	ucValue[4];		/*  metaData, KindAndCode ([0] が kind, [1] が code)  */
	unsigned char *	binaryData;		/*  malloc() されたメモリへのポインタ。先頭の sizeof(int32_t) バイトはデータの長さで、そのあとにデータ本体が続く。 */
	void *          anyPointer;     /*  任意のポインタ  */
} MDEventFieldData;

MDEventFieldCode	MDEventKindStringToEvent(const char *buf, MDEventFieldData *epout);
MDEventFieldCode	MDEventGTStringToEvent(const MDEvent *epin, const char *buf, MDEventFieldData *epout);
MDEventFieldCode	MDEventDataStringToEvent(const MDEvent *epin, const char *buf, MDEventFieldData *epout);

/*  イベントを MIDI メッセージに変換する（チャンネルイベントのみ）。buf は４バイト必要。 */
int		MDEventToMIDIMessage(const MDEvent *eventRef, unsigned char *buf);

/*  MIDI メッセージをイベントに変換する（チャンネルイベントのみ）。firstByte は最初のデータバイト（ランニングステータス可）、lastStatusByte はランニングステータスの時に仮定されるステータスバイト、getCharFunc は１バイト読み込むための関数へのポインタ、funcArgument は getCharFunc に渡す引数、outStatusByte はこのイベントのステータスバイトを受け取るためのポインタ。 */
MDStatus	MDEventFromMIDIMessage(MDEvent *eventRef, unsigned char firstByte, unsigned char lastStatusByte, int (*getCharFunc)(void *), void *funcArgument, unsigned char *outStatusByte);

/*  拍子記号イベントから、１小節の拍数、１拍の tick 数を求める  */
int		MDEventParseTimeSignature(const MDEvent *eptr, int32_t timebase, int32_t *outTickPerBeat, int32_t *outBeatPerMeasure);

char *	MDEventToString(const MDEvent *eptr, char *buf, int32_t bufsize);

/*  Parse "bar:beat:tick" string to three int32_t integers  */
int     MDEventParseTickString(const char *s, int32_t *bar, int32_t *beat, int32_t *tick);

int		MDEventSMFMetaNumberToEventKind(int smfMetaNumber);
int		MDEventMetaKindCodeToSMFMetaNumber(int kind, int code);

/*  Check if the event is allowable in the conductor/non-conductor tracks  */
int     MDEventIsEventAllowableInConductorTrack(const MDEvent *eptr);
int     MDEventIsEventAllowableInNonConductorTrack(const MDEvent *eptr);

/*  Get metronome bar and beat length from timebase and kMDEventTimeSignature event  */
int     MDEventCalculateMetronomeBarAndBeat(const MDEvent *eptr, int32_t timebase, int32_t *outTickPerMeasure, int32_t *outTickPerMetronomeBeat);

#ifdef __cplusplus
}
#endif

#endif  /*  __MDEvent__  */
