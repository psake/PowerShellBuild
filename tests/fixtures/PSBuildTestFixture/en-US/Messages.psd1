# Localized data for the fixture module.
#
# The fixture carries a culture directory because staging one is where
# psake/PowerShellBuild#210, #211 and #212 all live, and a fixture without one made every
# one of them invisible to the suite. This file is the "localized data" half of that: it is
# what used to be flattened into the output root by the depth-1 staging glob (#211), and it
# is a culture directory whose content is not an about topic, which is what keeps the
# content test in Build-PSBuildModule honest.
ConvertFrom-StringData @'
WidgetNotFound=No widget named [{0}] was found.
'@
