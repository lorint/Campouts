require './repository'
require './activity'
require './campout_scout'

class Campout
  include Repository

  attr_accessor :start_time, :end_time, :location

  has_many :activitys
  has_many :campout_scouts
end
