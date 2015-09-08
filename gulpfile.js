var gulp = require('gulp');
var gutil = require('gulp-util');
var coffee = require('gulp-coffee');
var requireFile = require('gulp-require-file');

gulp.task('coffee', function() {
  gulp.src('./src/javascripts/**/*.coffee')
    .pipe(
      coffee({
        bare: true
      })
        .on('error', gutil.log)
    )
    .pipe(gulp.dest('./dst/javascripts/'));
});


gulp.task("scripts", function() {
    return gulp.src('./src/javascripts/widget.coffee')
        .pipe(requireFile({}))
        .pipe(gulp.dest("./dst/"));
});
