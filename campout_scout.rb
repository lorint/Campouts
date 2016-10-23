require './repository'
require './scout'
require './campout'

class CampoutScout
  include Repository

  belongs_to :scout
  belongs_to :campout
end
