require './repository'

class Activity
  include Repository

  attr_accessor :name

  belongs_to :campout
end
