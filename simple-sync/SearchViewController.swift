//
//  SearchViewController.swift
//  search
//
//  Created by Wayne Carter on 6/24/23.
//

import UIKit
import CouchbaseLiteSwift

// MARK: - Search View Controller

class SearchViewController: CollectionViewController, UISearchResultsUpdating, UISearchBarDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let database: CouchbaseLiteSwift.Database
    private let collection: CouchbaseLiteSwift.Collection
    
    required init?(coder: NSCoder) {
        // Create the database.
        var database = try! CouchbaseLiteSwift.Database(name: "search")
        var collection = try! database.defaultCollection()
        
        // HACK: For existing databases that don't already have a vector index for the
        // images, delete the database and recreate it so that the demo data will be
        // reloaded and the vector index populated.
        // TODO: Once the async index updater is available, use that instead.
        if try! collection.indexes().contains("ImageVectorIndex") == false {
            try! database.delete()
            database = try! CouchbaseLiteSwift.Database(name: "search")
            collection = try! database.defaultCollection()
        }
        
        self.database = database
        self.collection = collection

        super.init(coder: coder)
        
        // If the database is empty, initialize it w/ the demo data.
        if collection.count == 0  {
            addDemoData(to: collection)
        }

        // Initialize the value index on the "name" field for fast sorting.
        let nameIndex = ValueIndexConfiguration(["name"])
        try! collection.createIndex(withName: "NameIndex", config: nameIndex)

        // Initialize the value index on the "category" field for fast predicates.
        let categoryIndex = ValueIndexConfiguration(["category"])
        try! collection.createIndex(withName: "CategoryIndex", config: categoryIndex)
        
        // Initialize the vector index on the "embedding" field for image search.
        var vectorIndex = VectorIndexConfiguration(expression: "embedding", dimensions: 768, centroids: 2)
        vectorIndex.metric = .cosine
        try! collection.createIndex(withName: "ImageVectorIndex", config: vectorIndex)

        // Initialize the full-text search index on the "name", "color", and "category" fields.
        let ftsIndex = FullTextIndexConfiguration(["name", "color", "category"])
        try! collection.createIndex(withName: "NameColorAndCategoryIndex", config: ftsIndex)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize the search controller results updater.
        searchController.searchResultsUpdater = self
        
        // Initialize the search bar.
        searchController.searchBar.placeholder = "Produce, Bakery, Dairy, and More"
        searchController.searchBar.scopeButtonTitles = ["All", "Produce", "Bakery", "Dairy"]
        
        // Initialize the "camera" button on the search bar.
        searchController.searchBar.setImage(UIImage(systemName: "camera"), for: .bookmark, state: .normal)
        searchController.searchBar.showsBookmarkButton = true
        searchController.searchBar.delegate = self
        
        // Load initial results.
        search(nil, category: nil, embedding: nil)
    }
    
    // MARK: - Search
    
    private func search(_ searchString: String?, category: String?, embedding: [NSNumber]?) {
        var select = [String]()
        var predicates = [String]()
        var orderBy = [String]()
        let parameters = Parameters()
        
        // Add the primary predicates.
        predicates.append("type = 'product'")
        predicates.append("AND ($category IS MISSING OR category = $category OR ARRAY_CONTAINS(category, $category))")
        
        // If there is an embedding, add the vector search components.
        if let embedding = embedding {
            select.append("VECTOR_DISTANCE(ImageVectorIndex) AS distance")
            predicates.append("AND VECTOR_MATCH(ImageVectorIndex, $embedding, 10)")
            predicates.append("AND VECTOR_DISTANCE(ImageVectorIndex) < 0.35")
            orderBy.append("VECTOR_DISTANCE(ImageVectorIndex)")
            parameters.setArray(MutableArrayObject(data: embedding), forName: "embedding")
        }

        // If there is an embedding, add the full-text search components.
        if var searchString = searchString?.uppercased(), !searchString.isEmpty {
            searchString = !searchString.hasSuffix("*") ? searchString.appending("*") : searchString
            
            predicates.append("AND MATCH(NameColorAndCategoryIndex, $search)")
            orderBy.append("RANK(NameColorAndCategoryIndex)")
            parameters.setString(searchString, forName: "search")
        }

        // If there is a selected category, add the category parameter.
        if let selectedCategory = category, selectedCategory != "All" {
            parameters.setString(selectedCategory, forName: "category")
        }
        
        // Set the defaults.
        select.insert(contentsOf: ["name","image"], at: 0)
        orderBy.append("name")
        
        // Expand the query string.
        let queryString = """
            SELECT \(select.joined(separator: ","))
            FROM _
            WHERE \(predicates.joined(separator: "\n"))
            ORDER BY \(orderBy.joined(separator: ","))
        """
        
        // Create the query.
        let query = try! database.createQuery(queryString)
        query.parameters = parameters
        
        do {
            // Execute the query and get the results.
            let results = try query.execute()
            
            // Enumerate through the query results and get the name and image.
            var searchResults = [SearchResult]()
            for result in results {
                if let name = result["name"].string,
                   let imageData = result["image"].blob?.content,
                   let image = UIImage(data: imageData)
                {
                    let distance = result["distance"].number?.doubleValue ?? .greatestFiniteMagnitude
                    let searchResult = SearchResult(name: name, image: image, distance: distance)
                    searchResults.append(searchResult)
                }
            }
            
            // If an embedding was provided then the query has a vector search
            // and a distance output. For these queries, post process and filter
            // any matches that are too far away from the closest match.
            if embedding != nil {
                // Get the minimum distance
                let minimumDistance: Double = {
                    let minimumResult = searchResults.min { a, b in a.distance < b.distance }
                    return minimumResult?.distance ?? .greatestFiniteMagnitude
                }()
                
                // Filter results that are too far away from the closest match.
                searchResults = searchResults.filter { searchResult in
                    searchResult.distance <= minimumDistance * 1.40
                }
            }
            
            // Set the search results.
            self.searchResults = searchResults
        } catch {
            // If the query fails, set an empty result. This is expected when the user is
            // typing an FTS expression but they haven't completed typing so the query is
            // invalid. e.g. "(blue OR"
            searchResults = []
        }
    }
    
    var searchString: String? {
        return searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var searchEmbedding: [NSNumber]?
    
    var searchCategory: String? {
        searchController.searchBar.scopeButtonTitles?[searchController.searchBar.selectedScopeButtonIndex]
    }
    
    func setSelectedImage(_ image: UIImage?, with embedding: [NSNumber]) {
        if let image = image {
            // Update the search UI.
            let bookmarkImage = self.searchController.searchBar.image(for: .bookmark, state: .normal)
            let bookmarkImageSize = bookmarkImage?.size ?? CGSize(width: 22, height: 22)
            let camaraImageSize = max(bookmarkImageSize.width, bookmarkImageSize.height)
            let cameraImage = image.zoomed(to: CGSize(width: camaraImageSize, height: camaraImageSize), cornerRadius: 0.25 * camaraImageSize)
            self.searchController.searchBar.setImage(cameraImage, for: .bookmark, state: .normal)
            
            // Update the search results.
            self.searchEmbedding = embedding
            self.search(self.searchString, category: self.searchCategory, embedding: self.searchEmbedding)
        } else {
            // Clear the search embedding.
            searchController.searchBar.setImage(UIImage(systemName: "camera"), for: .bookmark, state: .normal)
            searchEmbedding = nil
            
            search(searchString, category: searchCategory, embedding: searchEmbedding)
        }
    }
    
    func setSelectedImage(_ image: UIImage?) {
        if let image = image {
            // Generate the embedding for the selected image.
            embedding(for: image) { embedding in
                // Update the UI on the main thread.
                DispatchQueue.main.async {
                    // Update the search UI.
                    let bookmarkImage = self.searchController.searchBar.image(for: .bookmark, state: .normal)
                    let bookmarkImageSize = bookmarkImage?.size ?? CGSize(width: 22, height: 22)
                    let camaraImageSize = max(bookmarkImageSize.width, bookmarkImageSize.height)
                    let cameraImage = image.zoomed(to: CGSize(width: camaraImageSize, height: camaraImageSize), cornerRadius: 0.25 * camaraImageSize)
                    self.searchController.searchBar.setImage(cameraImage, for: .bookmark, state: .normal)
                    
                    // Update the search results.
                    self.searchEmbedding = embedding
                    self.search(self.searchString, category: self.searchCategory, embedding: self.searchEmbedding)
                }
            }
        } else {
            // Clear the search embedding.
            searchController.searchBar.setImage(UIImage(systemName: "camera"), for: .bookmark, state: .normal)
            searchEmbedding = nil
            
            search(searchString, category: searchCategory, embedding: searchEmbedding)
        }
    }
    
    private var searchResults = [SearchResult]() {
        didSet {
            // When the search results change, reload the collection view's data.
            collectionView.reloadData()
        }
    }
    
    private struct SearchResult {
        let name: String
        let image: UIImage
        let distance: Double
        
        init(name: String, image: UIImage, distance: Double) {
            self.name = name
            self.image = image
            self.distance = distance
        }
    }
    
    // MARK: - UISearchBarDelegate
    
    func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar) {
        presentImagePicker(for: searchBar)
    }
    
    func presentImagePicker(for searchBar: UISearchBar) {
        let actionSheet = UIAlertController(title: "Select a photo to search for similar items.", message: nil, preferredStyle: .actionSheet)
        
        // For iPads set the source view as required.
        if UIDevice.current.userInterfaceIdiom == .pad {
            actionSheet.popoverPresentationController?.sourceView = searchBar
        }
        
        func presentImagePicker(sourceType: UIImagePickerController.SourceType) {
            if UIImagePickerController.isSourceTypeAvailable(sourceType) {
                let imagePicker = UIImagePickerController()
                imagePicker.delegate = self
                imagePicker.sourceType = sourceType
                imagePicker.allowsEditing = false
                self.present(imagePicker, animated: true, completion: nil)
            }
        }
        
        // Option to choose photo from examples
        actionSheet.addAction(UIAlertAction(title: "Choose from Examples", style: .default, handler: { _ in
            let imagePicker = ImagePickerController()
            imagePicker.imageSelected = { [weak self] image in
                self?.setSelectedImage(image)
            }
            self.present(imagePicker, animated: true, completion: nil)
        }))
        
        // Check if the device has a camera
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            actionSheet.addAction(UIAlertAction(title: "Take Photo", style: .default, handler: { _ in
                presentImagePicker(sourceType: .camera)
            }))
        }
        
        // Option to choose photo from library
        actionSheet.addAction(UIAlertAction(title: "Choose from Library", style: .default, handler: { _ in
            presentImagePicker(sourceType: .photoLibrary)
        }))
        
        // If we have a search image, add an action for clearing it.
        if searchEmbedding != nil {
            actionSheet.addAction(UIAlertAction(title: "Clear Image", style: .destructive, handler: { _ in
                self.setSelectedImage(nil)
            }))
        }
        
        // Cancel action
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        // Present the action sheet to the user
        self.present(actionSheet, animated: true, completion: nil)
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        // Clear the selected category and image.
        searchController.searchBar.selectedScopeButtonIndex = 0
        setSelectedImage(nil)
    }
    
    // MARK: - UISearchResultsUpdating
    
    func updateSearchResults(for searchController: UISearchController) {
        // As the user types or clears the search, update the search results.
        search(searchString, category: searchCategory, embedding: searchEmbedding)
    }
    
    // MARK: - UICollectionViewDataSource

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return searchResults.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SearchCollectionViewCell.identifier, for: indexPath) as! SearchCollectionViewCell
        let searchResult = searchResults[indexPath.row]
        
        cell.label.text = searchResult.name
        cell.imageView.image = searchResult.image

        return cell
    }
    
    // MARK: - UIImagePickerControllerDelegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: nil)
        
        if let image = info[.originalImage] as? UIImage {
            setSelectedImage(image)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    // MARK: - Util
    
    private func addDemoData(to collection: CouchbaseLiteSwift.Collection) {
        let demoData: [[String : Any]] = [
            // Vegetables
            ["type":"product","name":"Hot Pepper","image":"🌶️","color":"red","category":"Produce"],
            ["type":"product","name":"Carrot","image":"🥕","color":"orange","category":"Produce"],
            ["type":"product","name":"Lettuce","image":"🥬","color":"green","category":"Produce"],
            ["type":"product","name":"Broccoli","image":"🥦","color":"green","category":"Produce"],
            ["type":"product","name":"Cucumber","image":"🥒","color":"green","category":"Produce"],
            ["type":"product","name":"Salad","image":"🥗","color":"green","category":"Produce"],
            ["type":"product","name":"Corn","image":"🌽","color":"yellow","category":"Produce"],
            ["type":"product","name":"Potato","image":"🥔","color":"brown","category":"Produce"],
            ["type":"product","name":"Garlic","image":"🧄","color":"brown","category":"Produce"],
            ["type":"product","name":"Onion","image":"🧅","color":"brown","category":"Produce"],
            ["type":"product","name":"Tomato","image":"🍅","color":"red","category":"Produce"],
            ["type":"product","name":"Bell Pepper","image":"🫑","color":"green","category":"Produce"],
            // Fruit
            ["type":"product","name":"Cherries","image":"🍒","color":"red","category":"Produce"],
            ["type":"product","name":"Strawberry","image":"🍓","color":"red","category":"Produce"],
            ["type":"product","name":"Grapes","image":"🍇","color":"purple","category":"Produce"],
            ["type":"product","name":"Red Apple","image":"🍎","color":"red","category":"Produce"],
            ["type":"product","name":"Watermelon","image":"🍉","color":["red","green"],"category":"Produce"],
            ["type":"product","name":"Tangerine","image":"🍊","color":"orange","category":"Produce"],
            ["type":"product","name":"Lemon","image":"🍋","color":"yellow","category":"Produce"],
            ["type":"product","name":"Pineapple","image":"🍍","color":"yellow","category":"Produce"],
            ["type":"product","name":"Banana","image":"🍌","color":"yellow","category":"Produce"],
            ["type":"product","name":"Avocado","image":"🥑","color":["green","yellow"],"category":"Produce"],
            ["type":"product","name":"Green Apple","image":"🍏","color":"green","category":"Produce"],
            ["type":"product","name":"Melon","image":"🍈","color":["green","yellow"],"category":"Produce"],
            ["type":"product","name":"Pear","image":"🍐","color":"green","category":"Produce"],
            ["type":"product","name":"Kiwi","image":"🥝","color":"green","category":"Produce"],
            ["type":"product","name":"Mango","image":"🥭","color":["red","yellow","green"],"category":"Produce"],
            ["type":"product","name":"Coconut","image":"🥥","color":["brown","white"],"category":"Produce"],
            ["type":"product","name":"Blueberries","image":"🫐","color":"blue","category":"Produce"],
            ["type":"product","name":"Ginger Root","image":"🫚","color":"brown","category":"Produce"],
            // Bakery
            ["type":"product","name":"Cake","image":"🍰","color":["yellow","white"],"category":"Bakery"],
            ["type":"product","name":"Cookie","image":"🍪","color":"brown","category":"Bakery"],
            ["type":"product","name":"Doughnut","image":"🍩","color":"brown","category":"Bakery"],
            ["type":"product","name":"Cupcake","image":"🧁","color":["yellow","white"],"category":"Bakery"],
            ["type":"product","name":"Bagel","image":"🥯","color":"brown","category":"Bakery"],
            ["type":"product","name":"Bread","image":"🍞","color":"brown","category":"Bakery"],
            ["type":"product","name":"Baguette","image":"🥖","color":"brown","category":"Bakery"],
            ["type":"product","name":"Pretzel","image":"🥨","color":"brown","category":"Bakery"],
            ["type":"product","name":"Croissant","image":"🥐","color":"brown","category":"Bakery"],
            // Dairy
            ["type":"product","name":"Cheese","image":"🧀","color":"yellow","category":"Dairy"],
            ["type":"product","name":"Butter","image":"🧈","color":"yellow","category":"Dairy"],
            ["type":"product","name":"Ice Cream","image":"🍨","color":["white","brown"],"category":"Dairy"]
        ]
        
        func imageFromString(_ string: String) -> UIImage? {
            let nsString = string as NSString
            let font = UIFont.systemFont(ofSize: 160)
            let stringAttributes = [NSAttributedString.Key.font: font]
            let imageSize = nsString.size(withAttributes: stringAttributes)

            let renderer = UIGraphicsImageRenderer(size: imageSize)
            let image = renderer.image { _ in
                nsString.draw( at: CGPoint.zero, withAttributes: stringAttributes)
            }

            return image
        }
        
        for (_, data) in demoData.enumerated() {
            // Add document with a generated image from it's image string.
            let document = MutableDocument(data: data)
            var image: UIImage? = nil
            if let imageString = document["image"].string {
                image = imageFromString(imageString)
                if let pngData = image?.pngData() {
                    document["image"].blob = Blob(contentType: "image/png", data: pngData)
                }
            }
            try! collection.save(document: document)
            
            // Generate an embedding for the image and update the document.
            embedding(for: image) { embedding in
                if let embedding = embedding {
                    document["embedding"].array = MutableArrayObject(data: embedding)
                    try! collection.save(document: document)
                }
            }
        }
    }
    
    private func embedding(for image: UIImage?, completion: @escaping ([NSNumber]?) -> Void) {
        Embeddings.foregroundFeatureEmbedding(from: image, fitTo: CGSize(width: 100, height: 100), completion: completion)
    }
}

// MARK: - Search Cell

class SearchCollectionViewCell: UICollectionViewCell {
    static let identifier = "Item"
    
    @IBOutlet weak var imageView: UIImageView! {
        didSet {
            imageView.layer.shadowColor = UIColor.black.cgColor
            imageView.layer.shadowOffset = CGSize(width: 0, height: 1)
            imageView.layer.shadowOpacity = 0.5
            imageView.layer.shadowRadius = 3
            imageView.layer.masksToBounds = false
        }
    }
    
    @IBOutlet weak var label: UILabel!
}

// MARK: - Collection View Controller

class CollectionViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout, UISearchControllerDelegate {
    let searchController = UISearchController(searchResultsController: nil)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Intialize the collection view layout.
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.minimumLineSpacing = 0
            layout.minimumInteritemSpacing = 0
            layout.sectionInset = .zero
        }
        
        // Initialize the search controller.
        searchController.delegate = self
        searchController.automaticallyShowsCancelButton = true
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.scopeBarActivation = .manual
        searchController.searchBar.showsScopeBar = true
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }
    
    // MARK: - UISearchControllerDelegate
    
    private var endSearchTapGestureRecognizer: UITapGestureRecognizer?
    
    func willPresentSearchController(_ searchController: UISearchController) {
        // Add the tap gesture recognizer when the search is presented and,
        // when tapped, dismiss the search.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissSearch))
        tapGestureRecognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGestureRecognizer)
        endSearchTapGestureRecognizer = tapGestureRecognizer
    }
    
    func willDismissSearchController(_ searchController: UISearchController) {
        // Remove the tap gesture recognizer when the search is dismissed.
        if let tapGestureRecognizer = endSearchTapGestureRecognizer {
            view.removeGestureRecognizer(tapGestureRecognizer)
            endSearchTapGestureRecognizer = nil
        }
    }
    
    @objc func dismissSearch() {
        searchController.searchBar.resignFirstResponder()
        if searchController.searchBar.text?.count == 0 {
            searchController.isActive = false
        }
    }
    
    // MARK: - UICollectionViewDataSource
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    // MARK: - UICollectionViewDelegateFlowLayout
    
    private let itemPadding: CGFloat = 20

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let numberOfItemsPerRow: CGFloat = {
            switch UIDevice.current.userInterfaceIdiom {
            case .pad:
                switch UIDevice.current.orientation {
                case .landscapeLeft, .landscapeRight: return 6
                default: return 4
                }
            default: return 2
            }
        }()

        let totalPadding = itemPadding * (numberOfItemsPerRow + 1)
        let availableWidth = collectionView.bounds.width - totalPadding
        let widthPerItem = floor(availableWidth / numberOfItemsPerRow)

        return CGSize(width: widthPerItem, height: widthPerItem) // Make cell square.
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return itemPadding
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: itemPadding, left: itemPadding, bottom: itemPadding, right: itemPadding)
    }
    
    // MARK: - Actions
    
    @IBAction func infoButtonPressed(_ sender: UIBarButtonItem) {
        let alert = Actions.info(for: "search")
        alert.popoverPresentationController?.sourceItem = sender
        alert.title = "Search using name, color, category, image, and more"
        present(alert, animated: true)
    }
    
    @IBAction func share(_ sender: UIBarButtonItem) {
        let activity = Actions.share(for: self)
        activity.popoverPresentationController?.sourceItem = sender
        present(activity, animated: true)
    }
}

private extension UIImage {
    func zoomed(to targetSize: CGSize, cornerRadius: CGFloat = 0) -> UIImage? {
        // Scale the image to fill the target size.
        let widthRatio = targetSize.width / self.size.width
        let heightRatio = targetSize.height / self.size.height
        let scaleFactor = max(widthRatio, heightRatio)
        let scaledWidth = self.size.width * scaleFactor
        let scaledHeight = self.size.height * scaleFactor
        let offsetX = (targetSize.width - scaledWidth) / 2.0 // Center horizontally
        let offsetY = (targetSize.height - scaledHeight) / 2.0 // Center vertically
        let scaledRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = self.scale
        rendererFormat.opaque = false

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        let centeredAndRoundedImage = renderer.image { context in
            UIColor.clear.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: targetSize))

            if cornerRadius > 0 {
                context.cgContext.beginPath()
                let path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height), cornerRadius: cornerRadius)
                path.addClip()
            }

            self.draw(in: scaledRect)
        }

        return centeredAndRoundedImage
    }
}
