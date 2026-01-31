#    Copyright (c) 2010-2024 Toshi Nagata. All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation version 2 of the License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

class Sequence

def change_control_number_ext
  hash = Dialog.run {
    layout(1,
	  layout(2,
	    item(:text, :title=>"Old control Number"),
	    item(:textfield, :width=>40, :range=>[0, 127], :tag=>"old"),
	    item(:text, :title=>"New control number"),
	    item(:textfield, :width=>40, :range=>[0, 127], :tag=>"new")),
	  item(:checkbox, :title=>"Change only editable tracks", :tag=>"editable_only"),
	  item(:checkbox, :title=>"Change only selected events", :tag=>"selection_only"))
  }
  if hash[:status] == 0
	old = hash["old"].to_i
	new = hash["new"].to_i
	editable_only = hash["editable_only"]
	selection_only = hash["selection_only"]
	puts "old = #{old}, new = #{new}, editable_only = #{editable_only}"
	each_track { |tr|
	  next if editable_only != 0 && !tr.editable?
	  tr.send(selection_only != 0 ? :each_selected : :each) { |p|
		if p.kind == :control && p.code == old
		  p.code = new
		end
	  }
	}
  end
end

def change_timebase
  timebase = self.timebase
  hash = Dialog.run("Change Timebase") {
    layout(1,
	  layout(2,
	    item(:text, :title=>"Current timebase = #{timebase}"),
		nil,
	    item(:text, :title=>"New timebase"),
	    item(:textfield, :width=>40, :range=>[24, 960], :tag=>"new")))
  }
#    p hash
  if hash[:status] == 0
	new = hash["new"].to_f
	mult = new / timebase
	each_track { |tr|
	  set1 = tr.all_events
	  set2 = tr.eventset { |p| p.kind == :note }
	  set2.modify_duration("*", mult)
	  set1.modify_tick("*", mult)
	}
	self.set_timebase(new)
  end
end

def randomize_ticks
  wd = (get_global_settings("randomize_tick_width") || "10").to_f
  if !self.has_selection
    message_box("No events are selected.", "Error", :ok);
    return
  end
  hash = Dialog.run("Randomize Ticks") {
    layout(1,
	  layout(1,
	    item(:text, :title=>"Randomize width (in milliseconds, 10-1000)"),
	    item(:textfield, :width=>40, :value=>wd.to_s, :range=>[10, 1000], :tag=>"width")))
  }
  if hash[:status] == 0
    wd = hash["width"].to_f
	set_global_settings("randomize_tick_width", wd.to_s)
    each_track { |tr|
      s = tr.selection
  	  t = []
  	  s.each { |p|
	    t1 = self.tick_to_time(p.tick)
	    t2 = t1 + (rand() - 0.5) * wd / 1000.0
	    t.push(Integer(self.time_to_tick(t2)))
	  }
      s.modify_tick(t)
    }
  end
end

def thin_events
  info = []
  nev = 0
  interval = (get_global_settings("thin_event_interval") || "10").to_f
  self.each_editable_track { |tr|
    sel = tr.selection
    if sel == nil || sel.count == 0
      next
    end
    pt = tr.pointer(sel[0])
    info.push([tr, pt, 0, sel, nil])
    nev += sel.count
  }
  if info.count == 0
    message_box("No events are selected", "Cannot process events", :ok, :error)
    return
  end
  #  Check the event kind
  typ = nil   #  Control: 0 to 127, Pitch bend: 128
  info.each { |ip|
    ip[3].each { |pt|
      if pt.kind == :control
        t = pt.code
      elsif pt.kind == :pitch_bend
        t = 128
      else
        message_box("Only control and pitch bend events can be processed.", "Cannot process events", :ok, :error)
        return
      end
      if typ == nil
        typ = t
      elsif typ != t
        message_box("All events must be the same type", "Cannot process events", :ok, :error)
        return
      end
    }
  }
  msg = "#{nev} events (" + (typ == 128 ? "Pitch bend" : "Control #{typ}") + ") found in #{info.count} track#{info.count > 1 ? "s" : ""}."
  hash = Dialog.run("Thin Events") {
    layout(1,
      item(:text, :title=>msg),
      layout(1,
        item(:text, :title=>"Minimum event interval (in milliseconds, 10-1000)"),
        item(:textfield, :width=>40, :value=>interval.to_s, :range=>[10, 1000], :tag=>"interval")))
  }
  return if hash[:status] != 0
  interval = hash["interval"].to_f
  set_global_settings("thin_event_interval", interval.to_s)
  next_tick = nil
  while true
    #  Look for the earliest event
    ip = info.min_by { |ip0| ip0[1].selected? ? ip0[1].tick : 0x7fffffff }
    pt = ip[1]
    break if !pt.selected?   #  All events are processed
    next_tick ||= pt.tick
    if ip[4] == nil || pt.tick >= next_tick
      ip[4] ||= []
      new_tick = pt.tick
      new_data = pt.data
      pt.next_in_selection
    else
      while pt.next_in_selection && pt.tick < next_tick
      end
      if pt.selected?
        if pt.tick == next_tick
          new_tick = pt.tick
          new_data = pt.data
          pt.next_in_selection
        else
          #  ip[4] is not empty, so we should have ip[4][-2]
          #  Interpolate the data value
          old_tick = ip[4][-2]
          old_data = ip[4][-1]
          val = Float(pt.data - old_data) / (pt.tick - old_tick) * (next_tick - old_tick) + old_data
          new_tick = next_tick
          new_data = val   #  val is left as float
        end
      else
        pt.last_in_selection
        new_tick = pt.tick
        new_data = pt.data
        pt.next_in_selection
      end
    end
    if ip[4].count > 0
      old_data = ip[4][-1]
      if old_data.to_i == new_data.to_i
        new_tick = nil  #  Skip this event
      end
    end
    if new_tick
      ip[4].push(new_tick, new_data)
    end
    next_tick = self.time_to_tick(self.tick_to_time(next_tick) + interval / 1000.0)
  end
  nev_new = 0
  info.each { |ip|
    ntr = Track.new
    (ip[4].count / 2).times { |i|
      tick = ip[4][i * 2]
      val = ip[4][i * 2 + 1].to_i
      if typ == 128
        ntr.add(tick, :pitch_bend, val)
      else
        ntr.add(tick, :control, typ, val)
      end
    }
    ip[0].cut(ip[3])
    ip[0].merge(ntr)
    nev_new += ntr.nevents
  }
  message_box("#{nev} events were replaced with #{nev_new} events.", "", :ok)
end

@@tremolo_len = "60"
@@tremolo_len2 = "90"
@@tremolo_accel = "4"
@@tremolo_ofs = "1"
@@tremolo_fluct = "10"

def create_tremolo
    values = [@@tremolo_len, @@tremolo_len2, @@tremolo_accel, @@tremolo_ofs, @@tremolo_fluct]
    hash = Dialog.run("Create Tremolo") {
        layout(1,
               layout(2,
                      item(:text, :title=>"Note length (ms)"),
                      item(:textfield, :width=>40, :tag=>"len", :value=>values[0]),
                      item(:text, :title=>"First note length (ms)"),
                      item(:textfield, :width=>40, :tag=>"len2", :value=>values[1]),
                      item(:text, :title=>"Accelerate count"),
                      item(:textfield, :width=>40, :tag=>"accel", :value=>values[2]),
                      item(:text, :title=>"Note offset"),
                      item(:textfield, :width=>40, :tag=>"ofs", :value=>values[3]),
                      item(:text, :title=>"Length fluctuate (%)"),
                      item(:textfield, :width=>40, :tag=>"fluct", :value=>values[4])))
    }
    #    p hash
    if hash[:status] == 0
        len = hash["len"].to_f / 1000
        len2 = hash["len2"].to_f / 1000
        if len2 == 0.0
            len2 = len
        end
        accel = hash["accel"].to_i
        ofs = hash["ofs"].to_i
        fluct = hash["fluct"].to_f / 100.0
        if fluct < 0.0
            fluct = 0.0
            elsif fluct >= 1.0
            fluct = 1.0
        end
        @@tremolo_len = hash["len"]
        @@tremolo_len2 = hash["len2"]
        @@tremolo_accel = hash["accel"]
        @@tremolo_ofs = hash["ofs"]
        @@tremolo_fluct = hash["fluct"]
        if accel <= 0
            r = 1.0
            else
            r = (len / len2) ** (1.0 / accel)
        end
        each_track { |tr|
            next if tr.selection.length == 0
            trnew = Track.new
            tr.each_selected { |p|
                next if p.kind != :note
                stick = p.tick
                etick = p.tick + p.duration
                vel = p.velocity
                ctick = stick  #  Start tick of next note
                code = p.code  #  Key number of next note
                clen = len2    #  Length of next note
                n = 0          #  Note count
                while (ctick < etick)
                    ntick = time_to_tick(tick_to_time(ctick) + clen * (1 + (rand - 0.5) * fluct * 2))
                    if ntick < ctick + 5
                        ntick = ctick + 5
                    end
                    break if ntick >= etick
                    cvel = vel * (1 + (rand - 0.5) * fluct * 2)
                    c = (code < 0 ? 0 : (code > 127 ? 127 : code))
                    trnew.add(ctick, c, ntick - ctick, cvel)
                    ctick = ntick
                    if n < accel
                        clen = clen * r
                        else
                        clen = len
                    end
                    if n % 2 == 0
                        code = code + ofs
                        else
                        code = code - ofs
                    end
                    n = n + 1
                end
            }
            tr.cut(tr.selection)
            tr.merge(trnew)
        }
    end
end

@@move_selected_events_to_track_no = 1

def move_selected_events_to_track
    values = [@@move_selected_events_to_track_no]
    names = []
    each_with_index { |tr, i|
        next if i == 0
        names.push("#{i}:#{tr.name}")
    }
    hash = Dialog.run("Move to Track") {
        layout(1,
               layout(2,
                      item(:text, :title=>"To track"),
                      item(:popup, :subitems=>names, :tag=>"totrack", :value=>values[0] - 1)))
    }
    #    p hash
    if hash[:status] == 0
        count = 0
        each_with_index { |tr, i|
            next if i == 0
            if tr.selection.length > 0
                count = count + 1
            end
        }
        if count == 0
            message_box("No movable events", "Cannot move events", :ok, :error)
            return
        end
        if count > 1
            if !message_box("Selected events are contained in #{count} tracks. Do you want to move all selected events to one track?")
                return
            end
        end
        totrack = hash["totrack"].to_i + 1
        @@move_selected_events_to_track_no = totrack
        trnew = Track.new
        trdest = track(totrack)
        each_with_index { |tr, i|
            next if i == 0 || tr.selection.length == 0
            tr.each_selected { |p|
                trnew.add(p.tick, p)
            }
            tr.cut(tr.selection)
        }
        trdest.merge(trnew)
    end
end

@@modify_durations_delta = "0"

def modify_durations
    values = [@@modify_durations_delta]
    hash = Dialog.run("Modify Durations") {
        layout(1,
               layout(2,
                      item(:text, :title=>"Duration delta (tick)"),
                      item(:textfield, :width=>40, :tag=>"delta", :value=>values[0])))
    }
    #    p hash
    if hash[:status] == 0
        delta = hash["delta"].to_f
        @@modify_durations_delta = hash["delta"]
        if delta != 0.0
            each_track { |tr|
                next if tr.selection.length == 0
                tr.each_selected { |p|
                    next if p.kind != :note
                    d = p.duration + delta
                    if d <= 0
                        d = 1
                    end
                    p.duration = d
                }
            }
        end
    end
end

def doReclock(guidetrack)
  tr = track(guidetrack)
  a = []
  tr.each { |pt| if pt.kind == :note; a.push([pt.tick, nil, tick_to_time(pt.tick)]); end }
  if a.length < 2
    message_box("At least 2 note events must be present in the guide track.", "Error", :ok)
    return
  end
  #  Pointer for time signature
  pt = track(0).pointer(-1)
  pos = -1
  tinfo = [0, timebase, timebase * 4]   #  tick, beat_ticks, bar_ticks
  #  Destination tick for each guide event
  tick = a[0][0]
  a.length.times { |i|
    pt.time_signature_at_tick(tick)
    if pt.position > pos
      d = pt.data
      ticks_per_beat = (d[2] > 0 ? timebase * d[2] / 24 : timebase * 4 / d[1])
      tinfo = [pt.tick, ticks_per_beat, timebase * 4 * d[0] / d[1]]
    end
    bar_top = tick - (tick - tinfo[0]) % tinfo[2]
    beat_top = tick - (tick - bar_top) % tinfo[1]
    next_beat_top = [beat_top + tinfo[1], bar_top + tinfo[2]].min
    if i == 0
      #  Replace tick with the nearest beat position
      if next_beat_top - tick < tick - beat_top
        tick = next_beat_top
      else
        tick = beat_top
      end
    else
      #  Proceed to the next beat position
      tick = next_beat_top
    end
    a[i][1] = tick
  }
  print "#{a.length} guide events were found\n"
  #  The original tempo value at the last guide event
  if pt.tempo_at_tick(a[-1][0])
    last_tempo = pt.data
  else
    last_tempo = 120.0
  end
  #  proc for calculating new tick
  newtick = lambda { |tick|
    if tick < a[0][0]
      return tick
    end
    tm = tick_to_time(tick)
    a0 = nil
    a.each { |a1|
      if tm < a1[2]  #  Never true for a[0]
        return ((tm - a0[2]) * (a1[1] - a0[1]) / (a1[2] - a0[2]) + a0[1]).to_i
      end
      a0 = a1
    }
    return tick - a0[0] + a0[1]  #  a0 is not nil, because a always has >=2 elements
  }
  #  Reclock each track, including the conductor track
  each_track { |tr|
    tick_set = EventSet.new(tr)
    tick_values = []
    duration_set = EventSet.new(tr)
    duration_values = []
    track_duration = tr.duration
    tr.each { |pt|
      tick = pt.tick
      ntick = newtick.call(tick)
      if tick != ntick
        tick_set.add(pt.position)
        tick_values.push(ntick)
      end
      if pt.kind == :note
        duration = pt.duration
        nduration = newtick.call(tick + duration) - ntick
        if nduration <= 0
          nduration = 1
        end
        if duration != nduration
          duration_set.add(pt.position)
          duration_values.push(nduration)
        end
      end
    }
    if tick_values.length > 0
      tick_set.modify_tick(tick_values)
    end
    if duration_values.length > 0
      duration_set.modify_duration(duration_values)
    end
    new_track_duration = newtick.call(track_duration)
    if tr.duration != new_track_duration
      tr.duration = new_track_duration
    end
    print "track #{tr.index}: #{tick_values.length} ticks #{duration_values.length} durations modified, track duration #{track_duration} to #{tr.duration}\n"
  }
  #  Remove the tempo event between a[0][1] and a[-1][1]
  tempo_set = EventSet.new(track(0))
  pt.position = -1
  while pt.next
    if pt.kind == :tempo && pt.tick >= a[0][1] && pt.tick <= a[-1][1]
      tempo_set.add(pt.position)
    end
  end
  if tempo_set.length > 0
    track(0).cut(tempo_set)
  end
  #  Insert new tempo events
  tr = Track.new
  a.length.times { |i|
    a0 = a[i]
    if i == a.length - 1
      new_tempo = last_tempo
    else
      a1 = a[i + 1]
      new_tempo = (a1[1] - a0[1]) * 60.0 / timebase / (a1[2] - a0[2])
    end
    ntick = a0[1]
    tr.add(ntick, :tempo, new_tempo)
  }
  track(0).merge(tr)
  print "tempo: #{tempo_set.length} events were removed and #{a.length} events were created\n"
end

def reclock
  names = []
  each_with_index { |tr, i|
    next if i == 0
    names.push("#{i}:#{tr.name}")
  }
  seq = self
  hash = Dialog.run("Reclock") {
    layout(1,
      layout(2,
        item(:text, :title=>"Guide Track"),
        item(:popup, :subitems=>names, :tag=>"guidetrack",
          :action=> proc { |it|
            a = []
            seq.track(it[:value] + 1).each { |pt| if pt.kind == :note; a.push(pt.tick); end }
            if a.length == 0
              s = "No note events"
            elsif a.length == 1
              s = "1 note event"
            else
              s = "#{a.length} note events\n" + seq.tick_to_measure(a[0]).join(":") + " - " + seq.tick_to_measure(a[-1]).join(":")
            end
            set_attr("note", :value, s)
          })),
      item(:textview, :width=>200, :tag=>"note", :value=>"\n", :editable=>false, :height=>36))
    g = item_with_tag("guidetrack")
    g[:action].call(g)
  }
  if hash[:status] == 0
    doReclock(hash["guidetrack"] + 1)
  end
end

end

register_menu("Change Timebase...", :change_timebase)
register_menu("Randomize Ticks...", :randomize_ticks, 1)
register_menu("Thin Selected Events...", :thin_events, 1)
register_menu("Create tremolo...", :create_tremolo, 1)
register_menu("Move selected events to track...", :move_selected_events_to_track, 1)
register_menu("Modify durations...", :modify_durations, 1)
register_menu("Reclock...", :reclock)
