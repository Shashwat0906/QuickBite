import UIKit
import MapKit
import DesignKit
import NetworkKit

/// Add / edit an address. The map pin sets the coordinates used for delivery
/// distance and the tracking map; the fields are pre-filled by reverse geocoding.
final class AddressFormViewController: UIViewController, MKMapViewDelegate {
    var onSaved: ((Address) -> Void)?

    private let env: AppEnvironment
    private let existing: Address?
    private let map = MKMapView()
    private let pin = UIImageView(image: UIImage(systemName: "mappin.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)))
    private let labelControl = UISegmentedControl(items: ["Home", "Work", "Other"])
    private let line1 = QBTextField(title: "House / flat / street", placeholder: "B-12, Barakhamba Road", contentType: .streetAddressLine1)
    private let line2 = QBTextField(title: "Landmark (optional)", placeholder: "Near metro gate 3", contentType: .streetAddressLine2)
    private let city = QBTextField(title: "City", placeholder: "New Delhi", contentType: .addressCity)
    private let pincode = QBTextField(title: "PIN code", placeholder: "110001", keyboard: .numberPad, contentType: .postalCode)
    private let defaultSwitch = UISwitch()
    private let saveButton = QBButton(title: "Save address")
    private var geocodeTask: Task<Void, Never>?

    init(env: AppEnvironment, existing: Address?) {
        self.env = env
        self.existing = existing
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = existing == nil ? "New address" : "Edit address"
        view.backgroundColor = DK.Color.background

        map.delegate = self
        map.layer.cornerRadius = DK.Radius.l
        map.translatesAutoresizingMaskIntoConstraints = false
        map.accessibilityLabel = "Map. Move it so the pin is on your door."
        pin.tintColor = DK.Color.primary
        pin.translatesAutoresizingMaskIntoConstraints = false
        map.addSubview(pin)
        let locate = UIButton(type: .system)
        locate.setImage(UIImage(systemName: "location.fill"), for: .normal)
        locate.backgroundColor = DK.Color.surface
        locate.layer.cornerRadius = 20
        locate.accessibilityLabel = "Use my current location"
        locate.translatesAutoresizingMaskIntoConstraints = false
        locate.addAction(UIAction { [weak self] _ in self?.useCurrentLocation() }, for: .touchUpInside)
        map.addSubview(locate)

        labelControl.selectedSegmentIndex = 0
        line1.textField.accessibilityIdentifier = "addressLine1"
        pincode.textField.accessibilityIdentifier = "addressPincode"
        city.textField.accessibilityIdentifier = "addressCity"
        saveButton.accessibilityIdentifier = "saveAddress"
        saveButton.addAction(UIAction { [weak self] _ in self?.save() }, for: .touchUpInside)
        let defaultRow = UIStackView(axis: .horizontal, spacing: DK.Spacing.s, alignment: .center, arrangedSubviews: [UILabel(font: DK.Font.body, text: "Make this my default"), UIView(), defaultSwitch])
        defaultSwitch.onTintColor = DK.Color.primary

        let hint = UILabel(font: DK.Font.caption, color: DK.Color.textSecondary, lines: 0, text: "Drag the map so the pin sits on your building.")
        let stack = UIStackView(axis: .vertical, spacing: DK.Spacing.l, arrangedSubviews: [map, hint, labelControl, line1, line2, city, pincode, defaultRow, saveButton])
        stack.setCustomSpacing(DK.Spacing.s, after: map)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: DK.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: DK.Spacing.page),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -DK.Spacing.page),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -DK.Spacing.l),
            map.heightAnchor.constraint(equalToConstant: 200),
            pin.centerXAnchor.constraint(equalTo: map.centerXAnchor),
            pin.bottomAnchor.constraint(equalTo: map.centerYAnchor),
            locate.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -DK.Spacing.s),
            locate.bottomAnchor.constraint(equalTo: map.bottomAnchor, constant: -DK.Spacing.s),
            locate.widthAnchor.constraint(equalToConstant: 40),
            locate.heightAnchor.constraint(equalToConstant: 40),
        ])

        let start: CLLocationCoordinate2D
        if let existing {
            start = CLLocationCoordinate2D(latitude: existing.latitude, longitude: existing.longitude)
            line1.text = existing.line1
            line2.text = existing.line2 ?? ""
            city.text = existing.city
            pincode.text = existing.pincode
            defaultSwitch.isOn = existing.isDefault
            labelControl.selectedSegmentIndex = ["Home", "Work"].firstIndex(of: existing.label) ?? 2
        } else {
            let current = env.deliveryLocation.current
            start = CLLocationCoordinate2D(latitude: current.latitude, longitude: current.longitude)
        }
        map.setRegion(MKCoordinateRegion(center: start, latitudinalMeters: 600, longitudinalMeters: 600), animated: false)
    }

    private func useCurrentLocation() {
        Task {
            guard let location = await env.location.currentLocation() else {
                toast("Location permission is off — move the map instead.", style: .error)
                return
            }
            map.setRegion(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 400, longitudinalMeters: 400), animated: true)
        }
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        // Prefill empty fields from the pin position (debounced by the map's own callback cadence).
        geocodeTask?.cancel()
        let center = CLLocation(latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude)
        geocodeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled, let placemark = await self.env.location.placemark(for: center) else { return }
            if self.line1.text.isEmpty { self.line1.text = [placemark.subThoroughfare, placemark.thoroughfare ?? placemark.name].compactMap { $0 }.joined(separator: " ") }
            if self.city.text.isEmpty { self.city.text = placemark.locality ?? "" }
            if self.pincode.text.isEmpty { self.pincode.text = placemark.postalCode ?? "" }
        }
    }

    private func save() {
        view.endEditing(true)
        line1.errorMessage = line1.text.trimmingCharacters(in: .whitespaces).count < 3 ? "Enter your house / street" : nil
        city.errorMessage = city.text.trimmingCharacters(in: .whitespaces).count < 2 ? "Enter your city" : nil
        pincode.errorMessage = pincode.text.range(of: #"^[1-9][0-9]{5}$"#, options: .regularExpression) == nil ? "Enter a valid 6-digit PIN code" : nil
        guard line1.errorMessage == nil, city.errorMessage == nil, pincode.errorMessage == nil else { return }

        let center = map.centerCoordinate
        let label = labelControl.titleForSegment(at: labelControl.selectedSegmentIndex) ?? "Other"
        let input = AddressInput(label: label, line1: line1.text, line2: line2.text.isEmpty ? nil : line2.text, city: city.text, pincode: pincode.text,
                                 latitude: center.latitude, longitude: center.longitude, isDefault: defaultSwitch.isOn)
        saveButton.isLoading = true
        Task {
            defer { saveButton.isLoading = false }
            do {
                let saved: Address
                if let existing {
                    saved = try await env.addresses.update(id: existing.id, input)
                } else {
                    saved = try await env.addresses.create(input)
                }
                Haptics.success()
                onSaved?(saved)
                navigationController?.popViewController(animated: true)
            } catch {
                showError(error, title: "Couldn't save address")
            }
        }
    }
}

/// Saved addresses: list, set default, edit, delete.
final class AddressesViewController: UITableViewController {
    enum Mode { case manage }

    private let env: AppEnvironment
    private var addresses: [Address] = []

    init(env: AppEnvironment, mode: Mode) {
        self.env = env
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Saved addresses"
        tableView.backgroundColor = DK.Color.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [weak self] _ in self?.edit(nil) })
        refreshControl = UIRefreshControl()
        refreshControl?.addAction(UIAction { [weak self] _ in self?.load() }, for: .valueChanged)
        load()
    }

    private func load() {
        Task {
            do {
                addresses = try await env.addresses.list()
                tableView.reloadData()
                if addresses.isEmpty {
                    let empty = StateView(.empty(symbol: "house", title: "No saved addresses", message: "Add one to check out faster."), actionTitle: "Add address") { [weak self] in self?.edit(nil) }
                    tableView.backgroundView = empty
                } else {
                    tableView.backgroundView = nil
                }
            } catch {
                showError(error)
            }
            refreshControl?.endRefreshing()
        }
    }

    private func edit(_ address: Address?) {
        let form = AddressFormViewController(env: env, existing: address)
        form.onSaved = { [weak self] _ in self?.load() }
        navigationController?.pushViewController(form, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { addresses.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let address = addresses[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = address.label + (address.isDefault ? "  ·  Default" : "")
        content.secondaryText = address.fullText
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: address.label == "Work" ? "briefcase.fill" : address.label == "Home" ? "house.fill" : "mappin.circle.fill")
        content.imageProperties.tintColor = DK.Color.primary
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        edit(addresses[indexPath.row])
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let address = addresses[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else { return done(false) }
            Task {
                do {
                    try await self.env.addresses.delete(id: address.id)
                    done(true)
                    self.load()
                } catch {
                    done(false)
                    self.showError(error)
                }
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

/// "Deliver to" picker: current GPS location or a saved address.
final class LocationPickerViewController: UITableViewController {
    private let env: AppEnvironment
    private weak var router: AppRouting?
    private var addresses: [Address] = []
    private var isLocating = false

    init(env: AppEnvironment, router: AppRouting) {
        self.env = env
        self.router = router
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Deliver to"
        tableView.backgroundColor = DK.Color.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        if env.session.isSignedIn {
            Task {
                addresses = (try? await env.addresses.list()) ?? []
                tableView.reloadData()
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return addresses.count
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 && !addresses.isEmpty ? "Saved addresses" : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        switch indexPath.section {
        case 0:
            content.text = isLocating ? "Locating…" : "Use my current location"
            content.secondaryText = env.location.isDenied ? "Location access is off in Settings" : "Using GPS"
            content.image = UIImage(systemName: "location.fill")
        case 1:
            let address = addresses[indexPath.row]
            content.text = address.label
            content.secondaryText = address.fullText
            content.image = UIImage(systemName: address.id == env.deliveryLocation.current.addressId ? "checkmark.circle.fill" : "mappin.circle")
        default:
            content.text = "Demo location: Connaught Place"
            content.secondaryText = "Where the sample cafés are"
            content.image = UIImage(systemName: "building.2.fill")
        }
        content.imageProperties.tintColor = DK.Color.primary
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 0:
            isLocating = true
            tableView.reloadRows(at: [indexPath], with: .none)
            Task {
                defer { isLocating = false; tableView.reloadData() }
                guard let location = await env.location.currentLocation() else {
                    toast("Couldn't get your location. Check Settings → Privacy → Location.", style: .error)
                    return
                }
                let label = await env.location.label(for: location)
                env.deliveryLocation.current = .init(title: label.title, subtitle: label.subtitle, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, addressId: nil)
                dismiss(animated: true)
            }
        case 1:
            env.deliveryLocation.use(addresses[indexPath.row])
            dismiss(animated: true)
        default:
            env.deliveryLocation.current = DeliveryLocationStore.fallback
            dismiss(animated: true)
        }
    }
}
