allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force every Android module (app + all plugin subprojects, e.g. :jni) onto the
// NDK that's actually installed and valid locally. flutter.ndkVersion resolves
// to 29.0.13113456, whose auto-download stalls on this network and leaves a
// corrupt folder with no source.properties — that's what fails the :jni CXX
// configuration. Pinning it in :app alone isn't enough, so set it for all
// subprojects here.
subprojects {
    val setNdk = {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            runCatching {
                androidExt.javaClass
                    .getMethod("setNdkVersion", String::class.java)
                    .invoke(androidExt, "28.2.13676358")
            }
        }
        Unit
    }
    // Some subprojects are already evaluated by the time this runs (the block
    // above forces it via evaluationDependsOn), and afterEvaluate throws on an
    // already-evaluated project — so configure those immediately instead.
    if (state.executed) {
        setNdk()
    } else {
        afterEvaluate { setNdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
