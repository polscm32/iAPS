import CoreData
import Foundation
import LoopKit
import SwiftUI
import Swinject

extension Bolus {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var unlockmanager: UnlockManager!
        @Injected() var apsManager: APSManager!
        @Injected() var broadcaster: Broadcaster!
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        // added for bolus calculator
        @Injected() var settings: SettingsManager!
        @Injected() var nsManager: NightscoutManager!
        @Injected() var carbsStorage: CarbsStorage!

        @Published var suggestion: Suggestion?
        @Published var predictions: Predictions?
        @Published var amount: Decimal = 0
        @Published var insulinRecommended: Decimal = 0
        @Published var insulinRequired: Decimal = 0
        @Published var units: GlucoseUnits = .mmolL
        @Published var percentage: Decimal = 0
        @Published var threshold: Decimal = 0
        @Published var maxBolus: Decimal = 0
        @Published var errorString: Decimal = 0
        @Published var evBG: Int = 0
        @Published var insulin: Decimal = 0
        @Published var isf: Decimal = 0
        @Published var error: Bool = false
        @Published var minGuardBG: Decimal = 0
        @Published var minDelta: Decimal = 0
        @Published var expectedDelta: Decimal = 0
        @Published var minPredBG: Decimal = 0
        @Published var waitForSuggestion: Bool = false
        @Published var carbRatio: Decimal = 0

        var waitForSuggestionInitial: Bool = false

        // added for bolus calculator
        @Published var recentGlucose: BloodGlucose?
        @Published var target: Decimal = 0
        @Published var cob: Decimal = 0
        @Published var iob: Decimal = 0

        @Published var currentBG: Decimal = 0
        @Published var fifteenMinInsulin: Decimal = 0
        @Published var deltaBG: Decimal = 0
        @Published var targetDifferenceInsulin: Decimal = 0
        @Published var targetDifference: Decimal = 0
        @Published var wholeCob: Decimal = 0
        @Published var wholeCobInsulin: Decimal = 0
        @Published var iobInsulinReduction: Decimal = 0
        @Published var wholeCalc: Decimal = 0
        @Published var insulinCalculated: Decimal = 0
        @Published var fraction: Decimal = 0
        @Published var useCalc: Bool = false
        @Published var basal: Decimal = 0
        @Published var fattyMeals: Bool = false
        @Published var fattyMealFactor: Decimal = 0
        @Published var useFattyMealCorrectionFactor: Bool = false
        @Published var displayPredictions: Bool = true

        @Published var currentBasal: Decimal = 0
        @Published var sweetMeals: Bool = false
        @Published var sweetMealFactor: Decimal = 0
        @Published var useSuperBolus: Bool = false
        @Published var superBolusInsulin: Decimal = 0

        @Published var meal: [CarbsEntry]?
        @Published var carbs: Decimal = 0
        @Published var fat: Decimal = 0
        @Published var protein: Decimal = 0
        @Published var note: String = ""

        @Published var date = Date()
        // @Published var protein: Decimal = 0
        // @Published var fat: Decimal = 0
        @Published var carbsRequired: Decimal?
        @Published var useFPUconversion: Bool = false
        @Published var dish: String = ""
        @Published var selection: Presets?
        @Published var summation: [String] = []
        @Published var maxCarbs: Decimal = 0
        // @Published var note: String = ""
        @Published var id_: String = ""
        @Published var summary: String = ""
        @Published var skipBolus: Bool = false

        let now = Date.now

        let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

        override func subscribe() {
            setupInsulinRequired()
            broadcaster.register(SuggestionObserver.self, observer: self)
            units = settingsManager.settings.units
            percentage = settingsManager.settings.insulinReqPercentage
            threshold = provider.suggestion?.threshold ?? 0
            maxBolus = provider.pumpSettings().maxBolus
            // added
            fraction = settings.settings.overrideFactor
            useCalc = settings.settings.useCalc
            fattyMeals = settings.settings.fattyMeals
            fattyMealFactor = settings.settings.fattyMealFactor
            sweetMeals = settings.settings.sweetMeals
            sweetMealFactor = settings.settings.sweetMealFactor
            displayPredictions = settings.settings.displayPredictions

            carbsRequired = provider.suggestion?.carbsReq
            maxCarbs = settings.settings.maxCarbs
            skipBolus = settingsManager.settings.skipBolusScreenAfterCarbs
            useFPUconversion = settingsManager.settings.useFPUconversion

            if waitForSuggestionInitial {
                apsManager.determineBasal()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] ok in
                        guard let self = self else { return }
                        if !ok {
                            self.waitForSuggestion = false
                            self.insulinRequired = 0
                            self.insulinRecommended = 0
                        }
                    }.store(in: &lifetime)
            }
            if let notNilSugguestion = provider.suggestion {
                suggestion = notNilSugguestion
                if let notNilPredictions = suggestion?.predictions {
                    predictions = notNilPredictions
                }
            }
        }

        func getCurrentBasal() {
            let basalEntries = provider.getProfile()

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            let currentTime = dateFormatter.string(from: Date())

            // loop throug entries and get current basal entry
            for (index, entry) in basalEntries.enumerated() {
                if let entryStartTimeDate = dateFormatter.date(from: entry.start) {
                    var entryEndTimeDate: Date

                    if index < basalEntries.count - 1 {
                        let nextEntry = basalEntries[index + 1]
                        if let nextEntryStartTimeDate = dateFormatter.date(from: nextEntry.start) {
                            let timeDifference = nextEntryStartTimeDate.timeIntervalSince(entryStartTimeDate)
                            entryEndTimeDate = entryStartTimeDate.addingTimeInterval(timeDifference)
                        } else {
                            continue
                        }
                    } else {
                        entryEndTimeDate = Date()
                    }
                    // if currenTime is between start and end of basal entry -> basal = currentBasal
                    if let currentTimeDate = dateFormatter.date(from: currentTime) {
                        if currentTimeDate >= entryStartTimeDate, currentTimeDate <= entryEndTimeDate {
                            if let basal = entry.rate as? Decimal {
                                currentBasal = basal
                                break
                            }
                        }
                    }
                }
            }
        }

        func getDeltaBG() {
            let glucose = provider.fetchGlucose()
            guard glucose.count >= 3 else { return }
            let lastGlucose = glucose.first?.glucose ?? 0
            let thirdLastGlucose = glucose[2]
            let delta = Decimal(lastGlucose) - Decimal(thirdLastGlucose.glucose)
            deltaBG = delta
        }

        // CALCULATIONS FOR THE BOLUS CALCULATOR
        func calculateInsulin() -> Decimal {
            var conversion: Decimal = 1.0
            if units == .mmolL {
                conversion = 0.0555
            }
            // insulin needed for the current blood glucose
            targetDifference = (currentBG - target) * conversion
            targetDifferenceInsulin = targetDifference / isf

            // more or less insulin because of bg trend in the last 15 minutes
            fifteenMinInsulin = (deltaBG * conversion) / isf

            // determine whole COB for which we want to dose insulin for and then determine insulin for wholeCOB
            wholeCob = cob + carbs
            wholeCobInsulin = wholeCob / carbRatio

            // determine how much the calculator reduces/ increases the bolus because of IOB
            iobInsulinReduction = (-1) * iob

            // adding everything together
            // add a calc for the case that no fifteenMinInsulin is available
            if deltaBG != 0 {
                wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin + fifteenMinInsulin)
            } else {
                // add (rare) case that no glucose value is available -> maybe display warning?
                // if no bg is available, ?? sets its value to 0
                if currentBG == 0 {
                    wholeCalc = (iobInsulinReduction + wholeCobInsulin)
                } else {
                    wholeCalc = (targetDifferenceInsulin + iobInsulinReduction + wholeCobInsulin)
                }
            }

            // apply custom factor at the end of the calculations
            let result = wholeCalc * fraction

            // apply custom factor if fatty meal toggle in bolus calc config settings is on and the box for fatty meals is checked (in RootView)
            if useFattyMealCorrectionFactor {
                insulinCalculated = result * fattyMealFactor
            } else if useSuperBolus {
                superBolusInsulin = sweetMealFactor * currentBasal
                insulinCalculated = result + superBolusInsulin
            } else {
                insulinCalculated = result
            }

            // display no negative insulinCalculated
            insulinCalculated = max(insulinCalculated, 0)
            insulinCalculated = min(insulinCalculated, maxBolus)

            return apsManager
                .roundBolus(amount: max(insulinCalculated, 0))
        }

        func add() {
            guard amount > 0 else {
                showModal(for: nil)
                return
            }

            let maxAmount = Double(min(amount, provider.pumpSettings().maxBolus))

            unlockmanager.unlock { authenticated in
                if authenticated {
                    self.apsManager.enactBolus(amount: maxAmount, isSMB: false)
                    self.showModal(for: nil)
                }
            }
        }

        func setupInsulinRequired() {
            DispatchQueue.main.async {
                self.insulinRequired = self.provider.suggestion?.insulinReq ?? 0

                var conversion: Decimal = 1.0
                if self.units == .mmolL {
                    conversion = 0.0555
                }

                self.evBG = self.provider.suggestion?.eventualBG ?? 0
                self.insulin = self.provider.suggestion?.insulinForManualBolus ?? 0
                self.target = self.provider.suggestion?.current_target ?? 0
                self.isf = self.provider.suggestion?.isf ?? 0
                self.iob = self.provider.suggestion?.iob ?? 0
                self.currentBG = (self.provider.suggestion?.bg ?? 0)
                self.cob = self.provider.suggestion?.cob ?? 0
                self.basal = self.provider.suggestion?.rate ?? 0
                self.carbRatio = self.provider.suggestion?.carbRatio ?? 0

                if self.settingsManager.settings.insulinReqPercentage != 100 {
                    self.insulinRecommended = self.insulin * (self.settingsManager.settings.insulinReqPercentage / 100)
                } else { self.insulinRecommended = self.insulin }

                self.errorString = self.provider.suggestion?.manualBolusErrorString ?? 0
                if self.errorString != 0 {
                    self.error = true
                    self.minGuardBG = (self.provider.suggestion?.minGuardBG ?? 0) * conversion
                    self.minDelta = (self.provider.suggestion?.minDelta ?? 0) * conversion
                    self.expectedDelta = (self.provider.suggestion?.expectedDelta ?? 0) * conversion
                    self.minPredBG = (self.provider.suggestion?.minPredBG ?? 0) * conversion
                } else { self.error = false }

                self.insulinRecommended = self.apsManager
                    .roundBolus(amount: max(self.insulinRecommended, 0))

                if self.useCalc {
                    self.getCurrentBasal()
                    self.getDeltaBG()
                    self.insulinCalculated = self.calculateInsulin()
                }
            }
        }

        func addCarbs() {
            guard carbs > 0 || fat > 0 || protein > 0 else { return }
            carbs = min(carbs, maxCarbs)
            id_ = UUID().uuidString

            let carbsToStore = [CarbsEntry(
                id: id_,
                createdAt: now,
                actualDate: date,
                carbs: carbs,
                fat: fat,
                protein: protein,
                note: note,
                enteredBy: CarbsEntry.manual,
                isFPU: false, fpuID: UUID().uuidString
            )]
            carbsStorage.storeCarbs(carbsToStore)

            if skipBolus {
                apsManager.determineBasalSync()
                showModal(for: nil)
            } else if carbs > 0 {
                saveToCoreData(carbsToStore)
                apsManager.determineBasalSync()
            } else {
                hideModal()
            }
        }

        func deletePreset() {
            if selection != nil {
                try? coredataContext.delete(selection!)
                try? coredataContext.save()
                carbs = 0
                fat = 0
                protein = 0
            }
            selection = nil
        }

        func removePresetFromNewMeal() {
            let a = summation.firstIndex(where: { $0 == selection?.dish! })
            if a != nil, summation[a ?? 0] != "" {
                summation.remove(at: a!)
            }
        }

        func addPresetToNewMeal() {
            let test: String = selection?.dish ?? "dontAdd"
            if test != "dontAdd" {
                summation.append(test)
            }
        }

        func addNewPresetToWaitersNotepad(_ dish: String) {
            summation.append(dish)
        }

        func addToSummation() {
            summation.append(selection?.dish ?? "")
        }

        func waitersNotepad() -> String {
            var filteredArray = summation.filter { !$0.isEmpty }

            if carbs == 0, protein == 0, fat == 0 {
                filteredArray = []
            }

            guard filteredArray != [] else {
                return ""
            }
            var carbs_: Decimal = 0.0
            var fat_: Decimal = 0.0
            var protein_: Decimal = 0.0
            var presetArray = [Presets]()

            coredataContext.performAndWait {
                let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
                try? presetArray = coredataContext.fetch(requestPresets)
            }
            var waitersNotepad = [String]()
            var stringValue = ""

            for each in filteredArray {
                let countedSet = NSCountedSet(array: filteredArray)
                let count = countedSet.count(for: each)
                if each != stringValue {
                    waitersNotepad.append("\(count) \(each)")
                }
                stringValue = each

                for sel in presetArray {
                    if sel.dish == each {
                        carbs_ += (sel.carbs)! as Decimal
                        fat_ += (sel.fat)! as Decimal
                        protein_ += (sel.protein)! as Decimal
                        break
                    }
                }
            }
            let extracarbs = carbs - carbs_
            let extraFat = fat - fat_
            let extraProtein = protein - protein_
            var addedString = ""

            if extracarbs > 0, filteredArray.isNotEmpty {
                addedString += "Additional carbs: \(extracarbs) ,"
            } else if extracarbs < 0 { addedString += "Removed carbs: \(extracarbs) " }

            if extraFat > 0, filteredArray.isNotEmpty {
                addedString += "Additional fat: \(extraFat) ,"
            } else if extraFat < 0 { addedString += "Removed fat: \(extraFat) ," }

            if extraProtein > 0, filteredArray.isNotEmpty {
                addedString += "Additional protein: \(extraProtein) ,"
            } else if extraProtein < 0 { addedString += "Removed protein: \(extraProtein) ," }

            if addedString != "" {
                waitersNotepad.append(addedString)
            }
            var waitersNotepadString = ""

            if waitersNotepad.count == 1 {
                waitersNotepadString = waitersNotepad[0]
            } else if waitersNotepad.count > 1 {
                for each in waitersNotepad {
                    if each != waitersNotepad.last {
                        waitersNotepadString += " " + each + ","
                    } else { waitersNotepadString += " " + each }
                }
            }
            return waitersNotepadString
        }

        func loadEntries(_ editMode: Bool) {
            if editMode {
                coredataContext.performAndWait {
                    var mealToEdit = [Meals]()
                    let requestMeal = Meals.fetchRequest() as NSFetchRequest<Meals>
                    let sortMeal = NSSortDescriptor(key: "createdAt", ascending: false)
                    requestMeal.sortDescriptors = [sortMeal]
                    requestMeal.fetchLimit = 1
                    try? mealToEdit = self.coredataContext.fetch(requestMeal)

                    self.carbs = Decimal(mealToEdit.first?.carbs ?? 0)
                    self.fat = Decimal(mealToEdit.first?.fat ?? 0)
                    self.protein = Decimal(mealToEdit.first?.protein ?? 0)
                    self.note = mealToEdit.first?.note ?? ""
                    self.id_ = mealToEdit.first?.id ?? ""
                }
            }
        }

        func saveToCoreData(_ stored: [CarbsEntry]) {
            coredataContext.performAndWait {
                let save = Meals(context: coredataContext)
                if let entry = stored.first {
                    save.createdAt = now
                    save.actualDate = entry.actualDate ?? Date.now
                    save.id = entry.id ?? ""
                    save.fpuID = entry.fpuID ?? ""
                    save.carbs = Double(entry.carbs)
                    save.fat = Double(entry.fat ?? 0)
                    save.protein = Double(entry.protein ?? 0)
                    save.note = entry.note
                    try? coredataContext.save()
                }
                print("meals 1: ID: " + (save.id ?? "").description + " FPU ID: " + (save.fpuID ?? "").description)
            }
        }
    }
}

extension Bolus.StateModel: SuggestionObserver {
    func suggestionDidUpdate(_: Suggestion) {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
        }
        setupInsulinRequired()
    }
}
