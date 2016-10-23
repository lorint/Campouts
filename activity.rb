require './repository'
require './campout'

class Activity
  include Repository

  attr_accessor :name

  belongs_to :campout
end
