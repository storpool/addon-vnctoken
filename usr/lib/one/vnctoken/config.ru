# -------------------------------------------------------------------------- #
# Copyright 2019-2020, StorPool                                              #
# Portions copyright OpenNebula Project, OpenNebula Systems                  #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

# If you are using self contained installation set this variable to the
# install location
#ENV['ONE_LOCATION']='/path/to/OpenNebula/install'

$: << '.'
require 'vnctoken-server'

run Sinatra::Application
