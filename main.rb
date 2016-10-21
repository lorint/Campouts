require 'pry'
require './campout_scout'
require './scout'
require './campout'

# JANKY!!!
CampoutScout.all = YAML.load_file("campoutscout.yml")

binding.pry
