require './repository'
# require './campout_scout'
# Mystery!!!
# load './campout_scout.rb'

class Scout
  include Repository
  attr_accessor :name

  has_many :campout_scouts
end
