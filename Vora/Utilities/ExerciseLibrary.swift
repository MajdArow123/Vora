//
//  ExerciseLibrary.swift
//  Vora
//
//  Created by Majd Arow on 2026-07-21.
//

import Foundation

enum ExerciseLibrary {
    static let all: [ExerciseDefinition] = [
        // Chest
        .init(
            id: "barbell-bench-press",
            name: "Barbell Bench Press",
            muscleGroup: .chest,
            mechanics: .compound,
            equipment: [.barbell, .bench],
            primaryMuscles: [.chest],
            secondaryMuscles: [.frontDelts, .triceps],
            techniqueCues: [
                "Retract your shoulder blades and keep them pinned to the bench",
                "Lower the bar to mid-chest with elbows about 45° from your torso",
                "Drive your feet into the floor",
                "Press up and slightly back toward your face",
            ]
        ),
        .init(
            id: "incline-barbell-press",
            name: "Incline Barbell Press",
            muscleGroup: .chest,
            mechanics: .compound,
            equipment: [.barbell, .bench],
            primaryMuscles: [.chest],
            secondaryMuscles: [.frontDelts, .triceps],
            techniqueCues: [
                "Set the bench between 30° and 45°",
                "Lower the bar to your upper chest, just below the collarbone",
                "Keep forearms vertical at the bottom",
                "Press up without letting your elbows flare wide",
            ]
        ),
        .init(
            id: "dumbbell-bench-press",
            name: "Dumbbell Bench Press",
            muscleGroup: .chest,
            mechanics: .compound,
            equipment: [.dumbbell, .bench],
            primaryMuscles: [.chest],
            secondaryMuscles: [.frontDelts, .triceps],
            techniqueCues: [
                "Keep your shoulder blades retracted throughout",
                "Lower until you feel a stretch across your chest",
                "Press the dumbbells up and slightly together without clanking",
            ]
        ),
        .init(
            id: "incline-dumbbell-press",
            name: "Incline Dumbbell Press",
            muscleGroup: .chest,
            mechanics: .compound,
            equipment: [.dumbbell, .bench],
            primaryMuscles: [.chest],
            secondaryMuscles: [.frontDelts, .triceps],
            techniqueCues: [
                "Set the bench to about 30°",
                "Lower with elbows around 45° until you feel an upper-chest stretch",
                "Drive the dumbbells up and slightly inward",
            ]
        ),
        .init(
            id: "dumbbell-fly",
            name: "Dumbbell Fly",
            muscleGroup: .chest,
            mechanics: .isolation,
            equipment: [.dumbbell, .bench],
            primaryMuscles: [.chest],
            secondaryMuscles: [.frontDelts],
            techniqueCues: [
                "Keep a soft bend in your elbows and hold it",
                "Lower in a wide arc until you feel a deep chest stretch",
                "Squeeze your chest to bring the arms together — don't press",
                "Stop the descent before your elbows drop below the bench",
            ]
        ),
        .init(
            id: "cable-crossover",
            name: "Cable Crossover",
            muscleGroup: .chest,
            mechanics: .isolation,
            equipment: [.cable],
            primaryMuscles: [.chest],
            secondaryMuscles: [.frontDelts],
            techniqueCues: [
                "Step forward into a split stance and lean slightly in",
                "Sweep in a wide arc, meeting the handles in front of your sternum",
                "Squeeze your chest for a beat at the midpoint",
                "Control the return — don't let the stack pull you back",
            ]
        ),
        .init(
            id: "cable-fly",
            name: "Cable Fly",
            muscleGroup: .chest,
            mechanics: .isolation,
            equipment: [.cable],
            primaryMuscles: [.chest],
            secondaryMuscles: [.frontDelts],
            techniqueCues: [
                "Set both pulleys at chest height and stand centered between them",
                "Keep a soft bend in your elbows and lock it in",
                "Bring the handles together in a wide arc straight in front of your chest",
                "Return slowly until you feel a stretch across your chest",
            ]
        ),
        .init(
            id: "machine-chest-press",
            name: "Machine Chest Press",
            muscleGroup: .chest,
            mechanics: .compound,
            equipment: [.machine],
            primaryMuscles: [.chest],
            secondaryMuscles: [.frontDelts, .triceps],
            techniqueCues: [
                "Set the seat so the handles sit at mid-chest height",
                "Keep your shoulder blades pulled back against the pad",
                "Press through the full range without slamming the lockout",
            ]
        ),
        .init(
            id: "push-up",
            name: "Push-Up",
            muscleGroup: .chest,
            mechanics: .compound,
            equipment: [.bodyweight],
            primaryMuscles: [.chest],
            secondaryMuscles: [.frontDelts, .triceps, .abs],
            techniqueCues: [
                "Hold a straight line from head to heels",
                "Hands slightly wider than shoulders, elbows about 45° out",
                "Lower until your chest nearly touches the floor",
                "Brace your core so your hips don't sag",
            ]
        ),
        .init(
            id: "dip",
            name: "Dip",
            muscleGroup: .chest,
            mechanics: .compound,
            equipment: [.bodyweight, .pullUpBar],
            primaryMuscles: [.chest],
            secondaryMuscles: [.frontDelts, .triceps],
            techniqueCues: [
                "Lean your torso slightly forward to load the chest",
                "Lower until your upper arms are parallel with the floor",
                "Keep your shoulders down, away from your ears",
                "Press up smoothly without snapping into lockout",
            ]
        ),
        // Back
        .init(
            id: "deadlift",
            name: "Deadlift",
            muscleGroup: .back,
            mechanics: .compound,
            equipment: [.barbell],
            primaryMuscles: [.glutes, .hamstrings, .lowerBack],
            secondaryMuscles: [.quads, .lats, .traps, .forearms],
            techniqueCues: [
                "Start with the bar over mid-foot, shins close",
                "Brace hard and pull the slack out of the bar before it leaves the floor",
                "Push the floor away, dragging the bar up your legs",
                "Lock out by squeezing your glutes, not leaning back",
            ]
        ),
        .init(
            id: "barbell-row",
            name: "Barbell Row",
            muscleGroup: .back,
            mechanics: .compound,
            equipment: [.barbell],
            primaryMuscles: [.lats, .upperBack],
            secondaryMuscles: [.rearDelts, .biceps, .lowerBack, .forearms],
            techniqueCues: [
                "Hinge to roughly 45° and hold that torso angle",
                "Pull the bar to your lower ribs",
                "Drive your elbows back and squeeze your shoulder blades together",
                "No jerking — if your torso heaves, the weight is too heavy",
            ]
        ),
        .init(
            id: "t-bar-row",
            name: "T-Bar Row",
            muscleGroup: .back,
            mechanics: .compound,
            equipment: [.barbell],
            primaryMuscles: [.lats, .upperBack],
            secondaryMuscles: [.rearDelts, .biceps, .lowerBack],
            techniqueCues: [
                "Hinge over the bar and keep your torso angle fixed",
                "Pull the handle into your chest with elbows tight",
                "Squeeze your shoulder blades together at the top",
                "Lower under control to a full stretch",
            ]
        ),
        .init(
            id: "dumbbell-row",
            name: "Dumbbell Row",
            muscleGroup: .back,
            mechanics: .compound,
            equipment: [.dumbbell, .bench],
            primaryMuscles: [.lats, .upperBack],
            secondaryMuscles: [.rearDelts, .biceps, .forearms],
            techniqueCues: [
                "Brace on the bench with a flat back",
                "Pull the dumbbell to your hip, not your shoulder",
                "Lead with your elbow and keep it close to your body",
                "Let your shoulder blade reach forward at the bottom",
            ]
        ),
        .init(
            id: "pull-up",
            name: "Pull-Up",
            muscleGroup: .back,
            mechanics: .compound,
            equipment: [.bodyweight, .pullUpBar],
            primaryMuscles: [.lats],
            secondaryMuscles: [.biceps, .upperBack, .rearDelts, .forearms],
            techniqueCues: [
                "Start each rep from a dead hang with shoulders engaged",
                "Drive your elbows down toward your hips",
                "Pull until your chin clears the bar",
                "Lower with control to a full stretch",
            ]
        ),
        .init(
            id: "chin-up",
            name: "Chin-Up",
            muscleGroup: .back,
            mechanics: .compound,
            equipment: [.bodyweight, .pullUpBar],
            primaryMuscles: [.lats, .biceps],
            secondaryMuscles: [.upperBack, .forearms],
            techniqueCues: [
                "Take an underhand, shoulder-width grip",
                "Pull your elbows down and back toward your ribs",
                "Get your chin over the bar without craning your neck",
                "Reach a full stretch at the bottom of every rep",
            ]
        ),
        .init(
            id: "lat-pulldown",
            name: "Lat Pulldown",
            muscleGroup: .back,
            mechanics: .compound,
            equipment: [.cable, .machine],
            primaryMuscles: [.lats],
            secondaryMuscles: [.biceps, .upperBack, .rearDelts],
            techniqueCues: [
                "Grip slightly wider than shoulders and sit tall",
                "Pull the bar to your upper chest, elbows down and back",
                "Squeeze your lats before controlling the bar back up",
                "Don't lean back and heave for extra reps",
            ]
        ),
        .init(
            id: "seated-cable-row",
            name: "Seated Cable Row",
            muscleGroup: .back,
            mechanics: .compound,
            equipment: [.cable, .machine],
            primaryMuscles: [.upperBack, .lats],
            secondaryMuscles: [.rearDelts, .biceps, .lowerBack],
            techniqueCues: [
                "Sit tall with knees softly bent",
                "Pull the handle to your stomach with elbows close",
                "Squeeze your shoulder blades together at the end",
                "Let your arms extend fully without rounding your back",
            ]
        ),
        .init(
            id: "face-pull",
            name: "Face Pull",
            muscleGroup: .back,
            mechanics: .isolation,
            equipment: [.cable],
            primaryMuscles: [.rearDelts],
            secondaryMuscles: [.traps, .upperBack],
            techniqueCues: [
                "Set the cable at face height",
                "Pull toward your forehead while spreading your hands apart",
                "Finish with thumbs pointing behind you",
                "Keep your shoulders down, away from your ears",
            ]
        ),
        .init(
            id: "machine-row",
            name: "Machine Row",
            muscleGroup: .back,
            mechanics: .compound,
            equipment: [.machine],
            primaryMuscles: [.upperBack, .lats],
            secondaryMuscles: [.rearDelts, .biceps],
            techniqueCues: [
                "Set the chest pad so the handles line up with your mid-chest",
                "Drive your elbows straight back",
                "Squeeze your shoulder blades at the end of each pull",
                "Control the return through a full stretch",
            ]
        ),
        // Shoulders
        .init(
            id: "overhead-press",
            name: "Overhead Press",
            muscleGroup: .shoulders,
            mechanics: .compound,
            equipment: [.barbell],
            primaryMuscles: [.frontDelts, .sideDelts],
            secondaryMuscles: [.triceps, .traps, .abs],
            techniqueCues: [
                "Squeeze your glutes and brace to keep your ribs down",
                "Start with the bar on your front delts, forearms vertical",
                "Press up and slightly back, bringing your head through at the top",
                "Finish with biceps by your ears",
            ]
        ),
        .init(
            id: "dumbbell-shoulder-press",
            name: "Dumbbell Shoulder Press",
            muscleGroup: .shoulders,
            mechanics: .compound,
            equipment: [.dumbbell],
            primaryMuscles: [.frontDelts, .sideDelts],
            secondaryMuscles: [.triceps],
            techniqueCues: [
                "Start with the dumbbells at shoulder height, palms forward",
                "Press to full extension without clanking them together",
                "Keep your core braced — don't flare your ribs",
                "Lower to about ear level with control",
            ]
        ),
        .init(
            id: "arnold-press",
            name: "Arnold Press",
            muscleGroup: .shoulders,
            mechanics: .compound,
            equipment: [.dumbbell],
            primaryMuscles: [.frontDelts, .sideDelts],
            secondaryMuscles: [.triceps],
            techniqueCues: [
                "Start with palms facing you at shoulder height",
                "Rotate your palms forward as you press up",
                "Reverse the rotation on the way down",
                "Keep your torso upright throughout",
            ]
        ),
        .init(
            id: "lateral-raise",
            name: "Lateral Raise",
            muscleGroup: .shoulders,
            mechanics: .isolation,
            equipment: [.dumbbell],
            primaryMuscles: [.sideDelts],
            secondaryMuscles: [.traps],
            techniqueCues: [
                "Lead with your elbows, not your hands",
                "Raise to shoulder height with a slight forward tilt",
                "Tilt the dumbbells as if pouring water at the top",
                "Lower slowly — resist on the way down",
            ]
        ),
        .init(
            id: "front-raise",
            name: "Front Raise",
            muscleGroup: .shoulders,
            mechanics: .isolation,
            equipment: [.dumbbell],
            primaryMuscles: [.frontDelts],
            secondaryMuscles: [.sideDelts],
            techniqueCues: [
                "Keep your torso still — no swinging",
                "Raise the dumbbells to shoulder height",
                "Lower under control, resisting gravity",
            ]
        ),
        .init(
            id: "rear-delt-fly",
            name: "Rear Delt Fly",
            muscleGroup: .shoulders,
            mechanics: .isolation,
            equipment: [.dumbbell],
            primaryMuscles: [.rearDelts],
            secondaryMuscles: [.upperBack, .traps],
            techniqueCues: [
                "Hinge until your torso is near parallel with the floor",
                "Sweep your arms wide with elbows slightly bent",
                "Lead with your pinkies and squeeze the rear delts",
                "Don't shrug — keep your traps quiet",
            ]
        ),
        .init(
            id: "cable-lateral-raise",
            name: "Cable Lateral Raise",
            muscleGroup: .shoulders,
            mechanics: .isolation,
            equipment: [.cable],
            primaryMuscles: [.sideDelts],
            secondaryMuscles: [.traps],
            techniqueCues: [
                "Stand side-on with the cable at its lowest setting",
                "Raise your arm out to shoulder height",
                "Keep your torso still — no leaning into the rep",
                "Lower slowly against the cable's pull",
            ]
        ),
        .init(
            id: "machine-shoulder-press",
            name: "Machine Shoulder Press",
            muscleGroup: .shoulders,
            mechanics: .compound,
            equipment: [.machine],
            primaryMuscles: [.frontDelts, .sideDelts],
            secondaryMuscles: [.triceps],
            techniqueCues: [
                "Set the seat so the handles start at shoulder height",
                "Keep your back against the pad and core braced",
                "Press to full extension without slamming the lockout",
            ]
        ),
        // Biceps
        .init(
            id: "barbell-curl",
            name: "Barbell Curl",
            muscleGroup: .biceps,
            mechanics: .isolation,
            equipment: [.barbell],
            primaryMuscles: [.biceps],
            secondaryMuscles: [.forearms],
            techniqueCues: [
                "Pin your elbows at your sides",
                "Curl without swinging your torso",
                "Squeeze at the top, then lower for a slow count",
                "Reach full extension at the bottom of each rep",
            ]
        ),
        .init(
            id: "preacher-curl",
            name: "Preacher Curl",
            muscleGroup: .biceps,
            mechanics: .isolation,
            equipment: [.barbell, .bench],
            primaryMuscles: [.biceps],
            secondaryMuscles: [.forearms],
            techniqueCues: [
                "Keep your upper arms flat on the pad the whole time",
                "Lower until your arms are almost fully extended",
                "Curl without lifting your elbows off the pad",
                "Pause briefly at the top squeeze",
            ]
        ),
        .init(
            id: "dumbbell-curl",
            name: "Dumbbell Curl",
            muscleGroup: .biceps,
            mechanics: .isolation,
            equipment: [.dumbbell],
            primaryMuscles: [.biceps],
            secondaryMuscles: [.forearms],
            techniqueCues: [
                "Keep your elbows pinned at your sides",
                "Rotate your palms up as you curl",
                "Control the lowering — no swinging",
            ]
        ),
        .init(
            id: "hammer-curl",
            name: "Hammer Curl",
            muscleGroup: .biceps,
            mechanics: .isolation,
            equipment: [.dumbbell],
            primaryMuscles: [.biceps, .forearms],
            secondaryMuscles: [],
            techniqueCues: [
                "Hold a neutral, palms-facing grip throughout",
                "Keep your elbows pinned to your sides",
                "Curl to shoulder height and squeeze",
                "Lower slowly without swinging",
            ]
        ),
        .init(
            id: "incline-dumbbell-curl",
            name: "Incline Dumbbell Curl",
            muscleGroup: .biceps,
            mechanics: .isolation,
            equipment: [.dumbbell, .bench],
            primaryMuscles: [.biceps],
            secondaryMuscles: [.forearms],
            techniqueCues: [
                "Set the bench to about 45° and let your arms hang straight down",
                "Keep your elbows behind your torso for the whole set",
                "Curl without drifting your elbows forward",
                "Feel the stretch at the fully lowered position",
            ]
        ),
        .init(
            id: "cable-curl",
            name: "Cable Curl",
            muscleGroup: .biceps,
            mechanics: .isolation,
            equipment: [.cable],
            primaryMuscles: [.biceps],
            secondaryMuscles: [.forearms],
            techniqueCues: [
                "Stand a step back so tension stays on at full extension",
                "Pin your elbows at your sides",
                "Squeeze hard at the top, then control the descent",
            ]
        ),
        // Triceps
        .init(
            id: "close-grip-bench-press",
            name: "Close-Grip Bench Press",
            muscleGroup: .triceps,
            mechanics: .compound,
            equipment: [.barbell, .bench],
            primaryMuscles: [.triceps],
            secondaryMuscles: [.chest, .frontDelts],
            techniqueCues: [
                "Grip just inside shoulder width",
                "Keep your elbows tucked close to your torso",
                "Lower the bar to your lower chest",
                "Lock out fully by driving through your triceps",
            ]
        ),
        .init(
            id: "skull-crusher",
            name: "Skull Crusher",
            muscleGroup: .triceps,
            mechanics: .isolation,
            equipment: [.barbell, .bench],
            primaryMuscles: [.triceps],
            secondaryMuscles: [.forearms],
            techniqueCues: [
                "Lower the bar to your forehead or just behind it",
                "Keep your upper arms vertical and still",
                "Extend by straightening the elbows only",
                "Don't let your elbows flare outward",
            ]
        ),
        .init(
            id: "overhead-triceps-extension",
            name: "Overhead Triceps Extension",
            muscleGroup: .triceps,
            mechanics: .isolation,
            equipment: [.dumbbell],
            primaryMuscles: [.triceps],
            secondaryMuscles: [],
            techniqueCues: [
                "Keep your elbows tight and pointed at the ceiling",
                "Lower behind your head until you feel a deep stretch",
                "Extend fully without moving your upper arms",
                "Keep your ribs down — don't arch to finish reps",
            ]
        ),
        .init(
            id: "triceps-kickback",
            name: "Triceps Kickback",
            muscleGroup: .triceps,
            mechanics: .isolation,
            equipment: [.dumbbell],
            primaryMuscles: [.triceps],
            secondaryMuscles: [],
            techniqueCues: [
                "Hinge with a flat back, upper arm parallel to the floor",
                "Freeze your upper arm — only the forearm moves",
                "Extend fully and squeeze for a beat",
                "Lower under control without dropping your elbow",
            ]
        ),
        .init(
            id: "triceps-pushdown",
            name: "Triceps Pushdown",
            muscleGroup: .triceps,
            mechanics: .isolation,
            equipment: [.cable],
            primaryMuscles: [.triceps],
            secondaryMuscles: [],
            techniqueCues: [
                "Pin your elbows to your sides",
                "Push down to full lockout and squeeze",
                "Let the bar rise only to chest height, elbows still",
                "Stay upright — don't lean over the stack",
            ]
        ),
        .init(
            id: "bench-dip",
            name: "Bench Dip",
            muscleGroup: .triceps,
            mechanics: .compound,
            equipment: [.bodyweight],
            primaryMuscles: [.triceps],
            secondaryMuscles: [.frontDelts, .chest],
            techniqueCues: [
                "Hands shoulder-width on the bench edge, fingers forward",
                "Keep your hips close to the bench as you lower",
                "Descend until your elbows reach about 90°",
                "Press up without shrugging your shoulders",
            ]
        ),
        // Quads
        .init(
            id: "back-squat",
            name: "Back Squat",
            muscleGroup: .quads,
            mechanics: .compound,
            equipment: [.barbell],
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings, .lowerBack, .abs],
            techniqueCues: [
                "Brace your core before you descend",
                "Break at the hips and knees together",
                "Track your knees over your toes",
                "Drive up through mid-foot with your chest up",
            ]
        ),
        .init(
            id: "front-squat",
            name: "Front Squat",
            muscleGroup: .quads,
            mechanics: .compound,
            equipment: [.barbell],
            primaryMuscles: [.quads],
            secondaryMuscles: [.glutes, .abs, .upperBack],
            techniqueCues: [
                "Keep your elbows high and chest tall",
                "Sit straight down between your heels",
                "Stay upright with the bar over mid-foot",
                "Lead with your elbows as you drive up",
            ]
        ),
        .init(
            id: "bulgarian-split-squat",
            name: "Bulgarian Split Squat",
            muscleGroup: .quads,
            mechanics: .compound,
            equipment: [.dumbbell, .bench],
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings],
            techniqueCues: [
                "Rear foot on the bench, front foot a long stride ahead",
                "Drop the back knee straight down",
                "Keep the front knee tracking over your toes",
                "Push through the front heel to stand",
            ]
        ),
        .init(
            id: "walking-lunge",
            name: "Walking Lunge",
            muscleGroup: .quads,
            mechanics: .compound,
            equipment: [.dumbbell],
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings, .calves],
            techniqueCues: [
                "Stride long enough to keep the front shin near vertical",
                "Lower the back knee toward the floor",
                "Push off the front heel into the next stride",
                "Keep your torso tall and core braced",
            ]
        ),
        .init(
            id: "goblet-squat",
            name: "Goblet Squat",
            muscleGroup: .quads,
            mechanics: .compound,
            equipment: [.kettlebell],
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.abs],
            techniqueCues: [
                "Hold the bell tight against your chest",
                "Let your elbows track inside your knees at the bottom",
                "Sit deep while keeping your chest tall",
                "Drive through mid-foot to stand",
            ]
        ),
        .init(
            id: "leg-press",
            name: "Leg Press",
            muscleGroup: .quads,
            mechanics: .compound,
            equipment: [.machine],
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings],
            techniqueCues: [
                "Place your feet shoulder-width at mid-platform",
                "Lower until your knees near 90°",
                "Don't let your lower back curl off the pad",
                "Press without snapping your knees into lockout",
            ]
        ),
        .init(
            id: "leg-extension",
            name: "Leg Extension",
            muscleGroup: .quads,
            mechanics: .isolation,
            equipment: [.machine],
            primaryMuscles: [.quads],
            secondaryMuscles: [],
            techniqueCues: [
                "Line your knees up with the machine's pivot",
                "Extend to full lockout and squeeze for a beat",
                "Lower slowly — resist the stack the whole way",
            ]
        ),
        .init(
            id: "hack-squat",
            name: "Hack Squat",
            muscleGroup: .quads,
            mechanics: .compound,
            equipment: [.machine],
            primaryMuscles: [.quads],
            secondaryMuscles: [.glutes],
            techniqueCues: [
                "Keep your back and hips pressed into the pads",
                "Lower to at least a 90° knee bend",
                "Drive through mid-foot with knees tracking over toes",
            ]
        ),
        // Hamstrings
        .init(
            id: "romanian-deadlift",
            name: "Romanian Deadlift",
            muscleGroup: .hamstrings,
            mechanics: .compound,
            equipment: [.barbell],
            primaryMuscles: [.hamstrings, .glutes],
            secondaryMuscles: [.lowerBack, .forearms],
            techniqueCues: [
                "Push your hips straight back with soft knees",
                "Keep the bar dragging against your legs",
                "Lower until you feel a strong hamstring stretch",
                "Squeeze your glutes to stand — don't yank with your back",
            ]
        ),
        .init(
            id: "good-morning",
            name: "Good Morning",
            muscleGroup: .hamstrings,
            mechanics: .compound,
            equipment: [.barbell],
            primaryMuscles: [.hamstrings],
            secondaryMuscles: [.glutes, .lowerBack],
            techniqueCues: [
                "Set the bar as you would for a squat, knees soft",
                "Hinge at the hips until your torso nears parallel",
                "Keep your spine neutral the entire time",
                "Squeeze your glutes to return upright",
            ]
        ),
        .init(
            id: "lying-leg-curl",
            name: "Lying Leg Curl",
            muscleGroup: .hamstrings,
            mechanics: .isolation,
            equipment: [.machine],
            primaryMuscles: [.hamstrings],
            secondaryMuscles: [.calves],
            techniqueCues: [
                "Line your knees up with the machine's pivot",
                "Keep your hips pressed into the bench",
                "Curl the pad as close to your glutes as you can",
                "Lower slowly to a full stretch",
            ]
        ),
        .init(
            id: "leg-curl",
            name: "Leg Curl",
            muscleGroup: .hamstrings,
            mechanics: .isolation,
            equipment: [.machine],
            primaryMuscles: [.hamstrings],
            secondaryMuscles: [.calves],
            techniqueCues: [
                "Line your knees up with the machine's pivot",
                "Keep your hips down and still throughout",
                "Curl the pad toward your glutes and pause briefly",
                "Lower under control to a full stretch",
            ],
            // Generic name from before the lying/seated variants existed.
            // Kept so logged history and old templates still resolve.
            isLegacyOnly: true
        ),
        .init(
            id: "seated-leg-curl",
            name: "Seated Leg Curl",
            muscleGroup: .hamstrings,
            mechanics: .isolation,
            equipment: [.machine],
            primaryMuscles: [.hamstrings],
            secondaryMuscles: [.calves],
            techniqueCues: [
                "Snug the lap pad down before starting",
                "Curl through the fullest range you can reach",
                "Pause at peak contraction",
                "Control the return — don't let the stack slam",
            ]
        ),
        .init(
            id: "nordic-curl",
            name: "Nordic Curl",
            muscleGroup: .hamstrings,
            mechanics: .isolation,
            equipment: [.bodyweight],
            primaryMuscles: [.hamstrings],
            secondaryMuscles: [.glutes, .calves],
            techniqueCues: [
                "Anchor your ankles securely and kneel tall",
                "Keep your hips extended — straight line from knees to head",
                "Lower as slowly as you possibly can",
                "Catch yourself with your hands and push back lightly",
            ]
        ),
        // Glutes
        .init(
            id: "hip-thrust",
            name: "Hip Thrust",
            muscleGroup: .glutes,
            mechanics: .compound,
            equipment: [.barbell, .bench],
            primaryMuscles: [.glutes],
            secondaryMuscles: [.hamstrings, .quads],
            techniqueCues: [
                "Rest your shoulder blades on the bench with the bar over your hips",
                "Tuck your chin and keep your ribs down",
                "Drive through your heels to full hip lockout",
                "Squeeze your glutes hard at the top for a beat",
            ]
        ),
        .init(
            id: "glute-bridge",
            name: "Glute Bridge",
            muscleGroup: .glutes,
            mechanics: .isolation,
            equipment: [.bodyweight],
            primaryMuscles: [.glutes],
            secondaryMuscles: [.hamstrings, .abs],
            techniqueCues: [
                "Bring your heels close to your glutes, feet flat",
                "Drive your hips to a straight line from knees to shoulders",
                "Squeeze your glutes at the top — don't arch your lower back",
                "Lower with control",
            ]
        ),
        .init(
            id: "cable-kickback",
            name: "Cable Kickback",
            muscleGroup: .glutes,
            mechanics: .isolation,
            equipment: [.cable],
            primaryMuscles: [.glutes],
            secondaryMuscles: [.hamstrings],
            techniqueCues: [
                "Hinge slightly forward, holding the frame",
                "Kick straight back with a nearly straight leg",
                "Squeeze the glute at full extension",
                "Don't arch your lower back for extra height",
            ]
        ),
        .init(
            id: "hip-abduction",
            name: "Hip Abduction",
            muscleGroup: .glutes,
            mechanics: .isolation,
            equipment: [.machine],
            primaryMuscles: [.glutes],
            secondaryMuscles: [],
            techniqueCues: [
                "Sit tall with your back against the pad",
                "Push your knees apart smoothly — no jerking",
                "Pause at the widest point",
                "Resist the pads on the way back in",
            ]
        ),
        .init(
            id: "kettlebell-swing",
            name: "Kettlebell Swing",
            muscleGroup: .glutes,
            mechanics: .compound,
            equipment: [.kettlebell],
            primaryMuscles: [.glutes, .hamstrings],
            secondaryMuscles: [.lowerBack, .abs, .forearms],
            techniqueCues: [
                "Hinge, don't squat — your arms stay loose",
                "Snap your hips forward to float the bell to chest height",
                "Let the bell swing back high between your thighs",
                "Keep your spine neutral as the bell descends",
            ]
        ),
        // Calves
        .init(
            id: "standing-calf-raise",
            name: "Standing Calf Raise",
            muscleGroup: .calves,
            mechanics: .isolation,
            equipment: [.machine],
            primaryMuscles: [.calves],
            secondaryMuscles: [],
            techniqueCues: [
                "Rise onto the balls of your feet as high as possible",
                "Pause at the top squeeze",
                "Lower until you feel a deep stretch",
                "Keep your knees straight but not locked",
            ]
        ),
        .init(
            id: "seated-calf-raise",
            name: "Seated Calf Raise",
            muscleGroup: .calves,
            mechanics: .isolation,
            equipment: [.machine],
            primaryMuscles: [.calves],
            secondaryMuscles: [],
            techniqueCues: [
                "Let your heels sink for a full stretch at the bottom",
                "Drive up onto the balls of your feet",
                "Pause at both the top and the stretched bottom",
            ]
        ),
        .init(
            id: "single-leg-calf-raise",
            name: "Single-Leg Calf Raise",
            muscleGroup: .calves,
            mechanics: .isolation,
            equipment: [.bodyweight],
            primaryMuscles: [.calves],
            secondaryMuscles: [],
            techniqueCues: [
                "Place the ball of your foot on an edge, heel hanging free",
                "Touch a wall lightly for balance only",
                "Full stretch at the bottom, full rise at the top",
                "Move slowly — no bouncing out of the stretch",
            ]
        ),
        // Core
        .init(
            id: "plank",
            name: "Plank",
            muscleGroup: .core,
            mechanics: .isolation,
            equipment: [.bodyweight],
            primaryMuscles: [.abs],
            secondaryMuscles: [.obliques, .glutes],
            techniqueCues: [
                "Elbows under shoulders, straight line from head to heels",
                "Squeeze your glutes and tuck your hips slightly",
                "Brace like you're about to take a punch",
                "Don't let your hips sag or pike",
            ]
        ),
        .init(
            id: "crunch",
            name: "Crunch",
            muscleGroup: .core,
            mechanics: .isolation,
            equipment: [.bodyweight],
            primaryMuscles: [.abs],
            secondaryMuscles: [.obliques],
            techniqueCues: [
                "Curl your ribs toward your pelvis",
                "Keep your lower back on the floor",
                "Exhale as you crunch up",
                "Don't pull on your neck",
            ]
        ),
        .init(
            id: "hanging-leg-raise",
            name: "Hanging Leg Raise",
            muscleGroup: .core,
            mechanics: .isolation,
            equipment: [.bodyweight, .pullUpBar],
            primaryMuscles: [.abs],
            secondaryMuscles: [.obliques, .forearms],
            techniqueCues: [
                "Start from a still dead hang with shoulders engaged",
                "Curl your pelvis up as you raise your legs",
                "Lower slowly without letting your body swing",
            ]
        ),
        .init(
            id: "ab-wheel-rollout",
            name: "Ab Wheel Rollout",
            muscleGroup: .core,
            mechanics: .isolation,
            equipment: [.bodyweight],
            primaryMuscles: [.abs],
            secondaryMuscles: [.obliques, .lats],
            techniqueCues: [
                "Tuck your pelvis and brace hard before each rep",
                "Roll out only as far as your lower back stays flat",
                "Drag yourself back with your abs, not your arms",
            ]
        ),
        .init(
            id: "cable-crunch",
            name: "Cable Crunch",
            muscleGroup: .core,
            mechanics: .isolation,
            equipment: [.cable],
            primaryMuscles: [.abs],
            secondaryMuscles: [.obliques],
            techniqueCues: [
                "Kneel and hold the rope beside your head",
                "Crunch your ribs toward your pelvis — hips stay still",
                "Round your upper back; it's not a hip hinge",
                "Control the stretch back up",
            ]
        ),
        .init(
            id: "russian-twist",
            name: "Russian Twist",
            muscleGroup: .core,
            mechanics: .isolation,
            equipment: [.bodyweight],
            primaryMuscles: [.obliques],
            secondaryMuscles: [.abs],
            techniqueCues: [
                "Lean back to about 45° with your chest up",
                "Rotate your shoulders, not just your arms",
                "Move with control from side to side",
                "Keep your spine long — don't slump",
            ]
        ),
    ]

    private static let byID: [String: ExerciseDefinition] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    private static let byLowercasedName: [String: ExerciseDefinition] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.name.lowercased(), $0) })

    static func definition(id: String) -> ExerciseDefinition? {
        byID[id]
    }

    /// Case-insensitive lookup by current display name.
    static func definition(named name: String) -> ExerciseDefinition? {
        byLowercasedName[name.lowercased()]
    }

    /// Older or alternate spellings found in shipped data (seed data,
    /// earlier builds) that unambiguously mean one library exercise, keyed
    /// by lowercased name. Only for resolving rows saved before IDs
    /// existed; never consulted for names chosen today. Ambiguous names
    /// ("bench", "squat") are deliberately absent.
    static let legacyAliases: [String: String] = [
        "bench press": "barbell-bench-press",
        "pull up": "pull-up",
        "push up": "push-up",
    ]

    /// Resolves a name stored before exercise IDs existed: an exact
    /// current name first, then a legacy alias. Used by ExerciseIDBackfill
    /// and the nil-ID matching fallback in ExerciseIdentity.
    static func legacyDefinition(lowercasedName: String) -> ExerciseDefinition? {
        byLowercasedName[lowercasedName]
            ?? legacyAliases[lowercasedName].flatMap { byID[$0] }
    }

    /// Whether the named exercise can be performed with the given
    /// equipment. Custom exercises (not in the library) have no known
    /// requirements and always count as available.
    static func isAvailable(name: String, with availableEquipment: Set<EquipmentType>) -> Bool {
        guard let definition = definition(named: name) else { return true }
        return definition.isAvailable(with: availableEquipment)
    }

    static let compoundRestSeconds = 120
    static let isolationRestSeconds = 90

    /// Default rest between sets: longer for compound lifts. Custom
    /// exercises (nil or unknown ID) get the isolation default.
    static func defaultRestSeconds(exerciseId: String?) -> Int {
        switch exerciseId.flatMap({ definition(id: $0) })?.mechanics {
        case .compound: compoundRestSeconds
        case .isolation, nil: isolationRestSeconds
        }
    }

    /// Picker search. Legacy-only entries are never offered.
    static func filtered(
        query: String,
        muscleGroup: MuscleGroup?,
        equipment: EquipmentType?
    ) -> [ExerciseDefinition] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return all.filter { exercise in
            !exercise.isLegacyOnly
                && (trimmed.isEmpty || exercise.name.localizedCaseInsensitiveContains(trimmed))
                && (muscleGroup == nil || exercise.muscleGroup == muscleGroup)
                && (equipment.map { exercise.equipment.contains($0) } ?? true)
        }
    }
}
