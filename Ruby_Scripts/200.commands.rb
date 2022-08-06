#    Copyright (c) 2010-2017 Toshi Nagata. All rights reserved.
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

end

register_menu("Change Timebase...", :change_timebase)
register_menu("Randomize Ticks...", :randomize_ticks, 1)
register_menu("Thin Selected Events...", :thin_events, 1)
register_menu("Create tremolo...", :create_tremolo, 1)
register_menu("Move selected events to track...", :move_selected_events_to_track, 1)
