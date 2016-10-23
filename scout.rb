require './repository'
require './campout_scout'

class Scout
  include Repository
  attr_accessor :name

  has_many :campout_scouts
end
