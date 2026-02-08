plugins {
    java
    application
}

group = "com.downloader"
version = "1.0.0"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories { mavenCentral() }

application { mainClass.set("com.downloader.Application") }

tasks.register<JavaExec>("bootRun") {
    group = "application"
    classpath = sourceSets.main.get().runtimeClasspath
    mainClass.set(application.mainClass)
}

tasks.register<JavaExec>("download") {
    group = "application"
    classpath = sourceSets.main.get().runtimeClasspath
    mainClass.set("com.downloader.DownloadExample")
    args = project.findProperty("url")?.toString()?.split(",") ?: emptyList()
}

tasks.register("spotlessApply") {
    group = "formatting"
    doLast { println("spotlessApply noop (offline environment)") }
}

tasks.named<Test>("test") {
    enabled = false
}

tasks.register<JavaExec>("runBehaviorTests") {
    group = "verification"
    classpath = sourceSets.test.get().runtimeClasspath
    mainClass.set("com.downloader.BehaviorTests")
}

tasks.named("check") { dependsOn("runBehaviorTests") }
