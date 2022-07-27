#!/usr/bin/ruby

require 'kconv'

#  Get the version string
#  version = "X.X.X"
#  date = "yyyymmdd"
version = nil
date = nil
svn_revision = nil
eval IO.read("Version")
eval IO.read("lastBuild.txt")

product_dir = ENV["BUILT_PRODUCTS_DIR"]  #  Should be exported from Xcode

#  Modify InfoPlist.strings
Dir["#{product_dir}/Alchemusica.app/Contents/Resources/*.lproj/InfoPlist.strings"].each { |nm|
  ary = []
  fp = open(nm, :mode=>"rb:BOM|utf-16")
  next unless fp
  fp.each_line { |s|
    s = s.encode("UTF-8")
    s.sub!(/Version [.0-9a-z]+/, "Version #{version} (rev #{svn_revision})")
    s = s.encode("UTF-16LE")
    ary.push(s)
  }
  fp.close()
  fp = open(nm, :mode=>"wb", :encoding=>"UTF-16LE")
  next unless fp
  fp.write("\uFEFF")   #  BOM
  ary.each { |s|
    fp.write(s)
  }
  fp.close()
}
