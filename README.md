adams-helper is used for generate constraints in MD ADAMS/View.

* `generateMatrix` is a preprocessor for `generateLink`, which generates distributed constraints
* `generateLink` read input file in csv format, which specified the position, type and other information of the constraints/motor/sensor. It outputs cmd format that can be run directly in ADAMS/View.

Sample File and usage can be found running the scripts without arguments. 
