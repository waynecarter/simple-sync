//
//  SearchViewController.swift
//  search
//
//  Created by Wayne Carter on 6/24/23.
//

import UIKit
import CouchbaseLiteSwift

// MARK: - Search View Controller

class SearchViewController: CollectionViewController, UISearchResultsUpdating {
    private let database: CouchbaseLiteSwift.Database
    private let collection: CouchbaseLiteSwift.Collection
    private let query: Query
    private let queryWithSearch: Query
    
    required init?(coder: NSCoder) {
        // Create the database and, if it is new, initialize it with the demo data.
        database = try! CouchbaseLiteSwift.Database(name: "search")
        collection = try! database.defaultCollection()
        if collection.count == 0  {
            Self.addDemoData(to: collection)
        }

        // Initialize the value index on the "name" field for fast sorting.
        let nameIndex = ValueIndexConfiguration(["name"])
        try! collection.createIndex(withName: "NameIndex", config: nameIndex)

        // Initialize the value index on the "category" field for fast predicates.
        let categoryIndex = ValueIndexConfiguration(["category"])
        try! collection.createIndex(withName: "CategoryIndex", config: categoryIndex)

        // Initialize the full-text search index on the "name", "color", and "category" fields.
        let ftsIndex = FullTextIndexConfiguration(["name", "color", "category"])
        try! collection.createIndex(withName: "NameColorAndCategoryIndex", config: ftsIndex)

        // Initialize the default query.
        query = try! database.createQuery("""
            SELECT name, image
            FROM _
            WHERE type = 'product'
                AND ($category IS MISSING OR category = $category OR ARRAY_CONTAINS(category, $category))
            ORDER BY name
        """)

        // Initialize the query with search.
        queryWithSearch = try! database.createQuery("""
            SELECT name, image
            FROM _
            WHERE type = 'product'
                AND ($category IS MISSING OR category = $category OR ARRAY_CONTAINS(category, $category))
                AND MATCH(NameColorAndCategoryIndex, $search)
            ORDER BY RANK(NameColorAndCategoryIndex), name
        """)

        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize the search controller results updater.
        searchController.searchResultsUpdater = self
        
        // Initialize the search bar.
        searchController.searchBar.placeholder = "Tops, Bottoms, Shoes, and More"
        searchController.searchBar.scopeButtonTitles = ["All", "Tops", "Bottoms", "Shoes"]
        
        // Load initial results.
        search(nil, category: nil)
    }
    
    // MARK: - Search
    
    private func search(_ searchString: String?, category: String?) {
        // Get the default query.
        var query = query
        
        // Create query parameters.
        let parameters = Parameters()

        // If there is a search value, use the query with search and add the
        // search parameter.
        if var searchString = searchString?.uppercased(), !searchString.isEmpty {
            query = queryWithSearch
            if !searchString.hasSuffix("*") {
                searchString = searchString.appending("*")
            }
            parameters.setString(searchString, forName: "search")
        }

        // If there is a selected category, add the category parameter.
        if let selectedCategory = category, selectedCategory != "All" {
            parameters.setString(selectedCategory, forName: "category")
        }

        // Set the query parameters.
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
                    let searchResult = SearchResult(name: name, image: image)
                    searchResults.append(searchResult)
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
    
    private var searchResults = [SearchResult]() {
        didSet {
            // When the search results change, reload the collection view's data.
            collectionView.reloadData()
        }
    }
    
    private struct SearchResult {
        let name: String
        let image: UIImage
    }
    
    // MARK: - UISearchResultsUpdating
    
    func updateSearchResults(for searchController: UISearchController) {
        // As the user types, update the search results.
        let searchString = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedCategory = searchController.searchBar.scopeButtonTitles?[searchController.searchBar.selectedScopeButtonIndex]
        search(searchString, category: selectedCategory)
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
    
    // MARK: - Util
    
    private static func addDemoData(to collection: CouchbaseLiteSwift.Collection) {
        let demoData: [[String : Any]] = [
            ["type":"product","name":"Polo","image":"👕","color":"blue","category":"Tops"],
            ["type":"product","name":"Jeans","image":"👖","color":"blue","category":"Bottoms"],
            ["type":"product","name":"Blouse","image":"👚","color":"pink","category":"Tops"],
            ["type":"product","name":"Dress","image":"👗","color":["green", "red"],"category":["Tops", "Bottoms"]],
            ["type":"product","name":"Shorts","image":"🩳","color":["orange", "white", "red"],"category":"Bottoms"],
            ["type":"product","name":"Socks","image":"🧦","color":["brown", "red"]],
            ["type":"product","name":"Hat","image":"🧢","color":"blue"],
            ["type":"product","name":"Scarf","image":"🧣","color":"red"],
            ["type":"product","name":"Gloves","image":"🧤","color":"green"],
            ["type":"product","name":"Coat","image":"🧥","color":"brown","category":"Tops"],
            ["type":"product","name":"Shirt","image":"👔","color":["blue", "yellow"],"category":"Tops"],
            ["type":"product","name":"Trainer","image":"👟","color":["gray", "white"],"category":"Shoes"],
            ["type":"product","name":"Flat","image":"🥿","color":"blue","category":"Shoes"],
            ["type":"product","name":"Hiking Boot","image":"🥾","color":["orange", "brown", "green"],"category":"Shoes"],
            ["type":"product","name":"Loafer","image":"👞","color":"brown","category":"Shoes"],
            ["type":"product","name":"Boot","image":"👢","color":"brown","category":"Shoes"],
            ["type":"product","name":"Sandal","image":"👡","color":"brown","category":"Shoes"],
            ["type":"product","name":"Flip Flop","image":"🩴","color":["green", "blue"],"category":"Shoes"]
        ]
        
        func image(fromString string: String) -> UIImage? {
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
            let document = MutableDocument(data: data)
            if let imageString = document["image"].string {
                let image = image(fromString: imageString)
                // Convert image to pngData
                if let pngData = image?.pngData() {
                    document["image"].blob = Blob(contentType: "image/png", data: pngData)
                }
            }
            try! collection.save(document: document)
        }
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
    
    private let itemPadding: CGFloat = 15

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
    
    // MARK: - Info
    
    @IBAction func infoButtonPressed(_ sender: UIBarButtonItem) {
        let alert = Alerts.info
        alert.popoverPresentationController?.sourceItem = sender
        alert.title = "Search using name, color, category, and more"
        
        self.present(alert, animated: true)
    }
}
